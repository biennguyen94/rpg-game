defmodule HacLong.Game.Session do
  @moduledoc """
  Tiến trình giữ nhân vật của một tài khoản khi người chơi đang online.

  Mọi lệnh của cùng một tài khoản đi qua đúng một tiến trình này nên được xử lý
  lần lượt, kể cả khi mở nhiều tab: không có chuyện hai thao tác cùng đọc một
  trạng thái cũ rồi ghi đè nhau. Sau mỗi thay đổi, trạng thái được ghi vào
  PostgreSQL và phát cho các tab khác qua PubSub.

  - Các tab đang mở (`GameChannel`) gắn vào Session bằng `attach/2`. Còn ít nhất một tab thì
    nhân vật có mặt trên bản đồ; tab cuối đóng thì rời bản đồ. Không còn tab nào và
    không ai dùng trong `@idle_timeout` thì tiến trình tự tắt.
  - Bước đi (`"move"`) rất nhiều nên không ghi database mỗi bước: vị trí được ghi dồn sau
    `@flush_ms`, khi đổi bản đồ, khi vào trận, khi đóng game và khi tiến trình tắt.
  - Bước đi bị giới hạn tốc độ (`@step_ms`) để không chạy nhanh bằng script; các lệnh khác
    (đánh, mua bán...) cũng vậy (`@act_ms`), nhanh hơn tay người bấm nhiều.
  """
  use GenServer, restart: :transient

  alias HacLong.Game.{
    Achievements,
    Characters,
    Commands,
    Daily,
    Engine,
    Names,
    Quests,
    Tower,
    Tutorial
  }

  alias HacLong.{Arena, Guilds, Mailbox, Party, World, WorldBoss}

  @idle_timeout :timer.minutes(10)
  @flush_ms 5_000
  # khoảng cách tối thiểu giữa hai bước, cho phép dồn vài bước khi mạng giật
  @step_ms 90
  @step_burst 4
  @act_ms 80
  @act_burst 10

  def topic(user_id), do: "player:#{user_id}"

  @doc "Trạng thái hiện tại (nil nếu chưa tạo nhân vật)."
  def get(user_id), do: call(user_id, :get)

  @doc "Tab `pid` mở game: nhân vật có mặt trên bản đồ. Trả về trạng thái hiện tại."
  def attach(user_id, pid), do: call(user_id, {:attach, pid})

  @doc "Chạy một lệnh từ client. Trả về `{kết_quả, nhân_vật}`."
  def command(user_id, cmd) when is_map(cmd), do: call(user_id, {:command, cmd, self()})

  @doc """
  Trùm thế giới đã gục hoặc bay đi (gọi từ `HacLong.WorldBoss`). `info`:
  `%{result: "win" | "fled", reward: nil | %{gold, xp, items, share}}`. Kết thúc trận đang
  đánh trùm (nếu có) và trao thưởng; người chơi không online thì vẫn nhận (lưu database).
  """
  def world_boss_end(user_id, info), do: call(user_id, {:world_boss_end, info})

  @doc """
  Đồng đội vừa hạ con quái đang đánh chung (gọi từ `HacLong.Party`). `info`:
  `%{key, n, xp, gold, killer}`. Trận của người này (nếu còn đánh) kết thúc bằng chiến thắng.
  """
  def shared_end(user_id, info), do: call(user_id, {:shared_end, info})

  @doc "Bang của người chơi vừa đổi: Session đang chạy thì nạp lại (không chạy thì thôi)."
  def refresh_guild(user_id) do
    case Registry.lookup(HacLong.Game.Registry, user_id) do
      [{pid, _}] -> GenServer.cast(pid, :refresh_guild)
      [] -> :ok
    end
  end

  defp call(user_id, msg, retry \\ true) do
    pid =
      case DynamicSupervisor.start_child(HacLong.Game.SessionSupervisor, {__MODULE__, user_id}) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    GenServer.call(pid, msg)
  catch
    # tiến trình vừa tự tắt vì rảnh đúng lúc gọi: khởi động lại và thử một lần nữa
    :exit, {reason, _} when retry and reason in [:noproc, :normal] -> call(user_id, msg, false)
  end

  def start_link(user_id) do
    GenServer.start_link(__MODULE__, user_id,
      name: {:via, Registry, {HacLong.Game.Registry, user_id}}
    )
  end

  @impl true
  def init(user_id) do
    # để `terminate/2` chạy khi server tắt (deploy) và ghi nốt vị trí chưa lưu
    Process.flag(:trap_exit, true)

    s = %{
      user_id: user_id,
      player: with_guild(Characters.load(user_id), user_id),
      tabs: %{},
      dirty: false,
      flush_timer: nil,
      steps: {@step_burst, now()},
      acts: {@act_burst, now()}
    }

    {:ok, s, @idle_timeout}
  end

  # Bang hội không lưu trong bảng characters: đọc từ HacLong.Guilds.
  defp with_guild(nil, _uid), do: nil
  defp with_guild(p, uid), do: Map.put(p, :guild, Guilds.brief(uid))

  @impl true
  def handle_call(msg, from, s), do: handle(msg, from, fresh(s))

  @impl true
  def handle_cast(:refresh_guild, %{player: nil} = s), do: {:noreply, s, timeout(s)}

  def handle_cast(:refresh_guild, s) do
    p = with_guild(s.player, s.user_id)
    s = %{s | player: p}
    broadcast(s, p, nil)
    if map_size(s.tabs) > 0, do: World.refresh(p, s.user_id)
    Phoenix.PubSub.broadcast(HacLong.PubSub, topic(s.user_id), {:guild, p.guild})
    {:noreply, s, timeout(s)}
  end

  # Sang ngày mới thì đổi việc hằng ngày (lưu cùng lần ghi tiếp theo).
  defp fresh(s), do: %{s | player: Daily.ensure(s.player, Daily.today())}

  defp handle(:get, _from, s), do: reply(s.player, s)

  defp handle({:attach, pid}, _from, s) do
    if map_size(s.tabs) == 0, do: World.enter(s.player, s.user_id)
    s = %{s | tabs: Map.put(s.tabs, Process.monitor(pid), pid)}
    reply(s.player, s)
  end

  defp handle({:command, %{"act" => act} = cmd, origin}, _from, s)
       when act in ["move", "teleport"] do
    case take(s, :steps, @step_ms, @step_burst) do
      {:ok, s} ->
        {result, player} = run_move(s, cmd)
        {player, notes} = checks(player)
        old = s.player

        s =
          cond do
            player == old ->
              s

            old.pos.map != player.pos.map or player.battle != nil or
              player.waystones != old.waystones or player[:tower] != old[:tower] or
              player[:tutorial] != old[:tutorial] or
                player[:achievements] != old[:achievements] ->
              save(s, player)

            true ->
              s |> Map.put(:player, player) |> mark_dirty()
          end

        if player != old, do: broadcast(s, player, origin)
        Enum.each(notes, &notify(s, &1))
        reply({result, player}, s)

      :too_fast ->
        reply({%{ok: false}, s.player}, s)
    end
  end

  defp handle({:command, cmd, origin}, _from, s) do
    case take(s, :acts, @act_ms, @act_burst) do
      {:ok, s} -> run_command(s, cmd, origin)
      :too_fast -> reply({%{ok: false, msg: "Thao tác quá nhanh."}, s.player}, s)
    end
  end

  defp handle({:shared_end, info}, _from, %{player: %{battle: %{over: false} = b}} = s) do
    if b[:encounter][:shared] == info.key do
      old = s.player
      p = shared_reward(old, info)
      {_, p} = Engine.finish_win(p)
      log = p.battle.log ++ [%{text: "Đồng đội ra đòn kết liễu!", kind: "info"}]
      p = put_in(p.battle.log, Enum.take(log, -60))
      p = battle_over(s, old, p)
      s = save(s, p)
      broadcast(s, p, nil)
      reply(:ok, s)
    else
      reply(:ok, s)
    end
  end

  defp handle({:shared_end, _info}, _from, s), do: reply(:ok, s)

  defp handle({:world_boss_end, _info}, _from, %{player: nil} = s), do: reply(:ok, s)

  defp handle({:world_boss_end, info}, _from, s) do
    old = s.player
    p = s.player

    p =
      if World.world_battle?(p),
        do:
          end_world_battle(
            p,
            info.result,
            if(info.result == "win",
              do: "#{WorldBoss.name()} đã gục ngã!",
              else: "#{WorldBoss.name()} đã bay đi."
            )
          ),
        else: p

    {p, notice} =
      case info.reward do
        nil ->
          {p, if(info.result == "win", do: nil, else: "#{WorldBoss.name()} đã bay đi.")}

        # không online: gửi thưởng qua hộp thư, lần sau vào game thấy ngay
        r when map_size(s.tabs) == 0 ->
          xp = min(r.xp, 3 * Engine.xp_to_next(p.level))

          Mailbox.send(s.user_id, %{
            subject: "Thưởng trùm thế giới",
            body: "#{WorldBoss.name()} đã gục ngã. Bạn gây #{r.share}% sát thương.",
            gold: r.gold,
            xp: xp,
            items: r.items
          })

          {p, nil}

        r ->
          # không cho người cấp thấp nhảy vọt quá nhiều cấp nhờ một trận
          xp = min(r.xp, 3 * Engine.xp_to_next(p.level))
          p = %{p | gold: p.gold + r.gold}
          p = Enum.reduce(r.items, p, fn {id, n}, p -> Engine.add_item(p, id, n) end)
          {levels, p} = Engine.gain_xp(p, xp)

          text =
            "Thưởng trùm thế giới (#{r.share}% sát thương): +#{r.gold} vàng, +#{xp} kinh nghiệm#{if r.items != %{}, do: ", Vảy Cổ Long", else: ""}."

          p =
            if World.world_battle?(p) do
              b = p.battle
              reward = %{xp: xp, gold: r.gold, items: Map.keys(r.items), levels: levels}

              %{
                p
                | battle: %{
                    b
                    | reward: reward,
                      log: Enum.take(b.log ++ [%{text: text, kind: "win"}], -60)
                  }
              }
            else
              p
            end

          {p, text}
      end

    s = if p != old, do: save(s, p), else: s
    broadcast(s, p, nil)
    if notice, do: Phoenix.PubSub.broadcast(HacLong.PubSub, topic(s.user_id), {:notice, notice})
    reply(:ok, s)
  end

  # Tạo nhân vật: kiểm tra tên hợp lệ và chưa ai dùng (cần database nên làm ở đây).
  defp run_command(%{player: nil} = s, %{"act" => "create"} = cmd, origin) do
    with {:ok, name} <- Names.validate(cmd["name"]),
         false <- Characters.name_taken?(name) do
      run_command_(s, Map.put(cmd, "name", name), origin)
    else
      {:error, msg} -> reply({%{ok: false, msg: msg}, nil}, s)
      true -> reply({%{ok: false, msg: "Tên này đã có người dùng."}, nil}, s)
    end
  rescue
    # hai người cùng lấy một tên đúng lúc: ràng buộc duy nhất trong database chặn người sau
    Ecto.ConstraintError -> reply({%{ok: false, msg: "Tên này đã có người dùng."}, nil}, s)
  end

  # Mở thư: đánh dấu thư đã nhận và ghi nhân vật trong cùng một transaction.
  defp run_command(%{player: p} = s, %{"act" => "mail_claim", "id" => id}, origin)
       when p != nil do
    case Mailbox.claim(s.user_id, id, p, &Characters.save!(s.user_id, &1)) do
      {:ok, msg, player} ->
        s = cancel_flush(%{s | player: player, dirty: false})
        broadcast(s, player, origin)
        reply({%{ok: true, msg: msg}, player}, s)

      {:error, msg} ->
        reply({%{ok: false, msg: msg}, p}, s)
    end
  end

  # Lập bang, góp quỹ: trừ vàng và ghi nhân vật trong cùng transaction với bảng bang hội.
  defp run_command(%{player: p} = s, %{"act" => act} = cmd, origin)
       when p != nil and act in ["guild_create", "guild_donate"] do
    save = &Characters.save!(s.user_id, &1)

    result =
      if act == "guild_create",
        do: Guilds.create(s.user_id, cmd["name"], cmd["tag"], p, save),
        else: Guilds.donate(s.user_id, cmd["amount"], p, save)

    case result do
      {:ok, msg, player} ->
        player = with_guild(player, s.user_id)
        s = cancel_flush(%{s | player: player, dirty: false})
        broadcast(s, player, origin)
        reply({%{ok: true, msg: msg}, player}, s)

      {:error, msg} ->
        reply({%{ok: false, msg: msg}, p}, s)
    end
  end

  defp run_command(s, cmd, origin), do: run_command_(s, cmd, origin)

  defp run_command_(s, cmd, origin) do
    old = s.player
    {result, player} = run(s, old, cmd)
    # nhân vật vừa tạo cũng có ngay việc hằng ngày
    player = s |> after_command(old, player, cmd) |> Daily.ensure(Daily.today())
    # nhân vật vừa tạo: gắn thông tin bang (chưa có) như lúc nạp từ database
    player = if player && old == nil, do: with_guild(player, s.user_id), else: player
    {player, notes} = checks(player)

    s =
      if player != old do
        broadcast(s, player, origin)
        # đổi đồ, lên cấp, dắt thú khác: người cùng bản đồ thấy ngay
        if player && old && map_size(s.tabs) > 0 && World.info(player) != World.info(old),
          do: World.refresh(player, s.user_id)

        if player, do: save(s, player), else: delete(s)
      else
        s
      end

    Enum.each(notes, &notify(s, &1))
    reply({result, player}, s)
  end

  # Hướng dẫn người mới và thành tựu: tính lại sau mỗi thay đổi, trả về các thông báo mới.
  defp checks(player) do
    {player, tut} = Tutorial.check(player)
    {player, ach} = Achievements.check(player)
    {player, Enum.reject([tut, ach], &is_nil/1)}
  end

  # Thông báo riêng cho người chơi này (hiện ở mọi tab đang mở), vd. bước hướng dẫn mới.
  defp notify(_s, nil), do: :ok

  defp notify(s, text),
    do: Phoenix.PubSub.broadcast(HacLong.PubSub, topic(s.user_id), {:notice, text})

  # Đánh trùm thế giới: máu trùm là máu chung ở HacLong.WorldBoss. Trước lượt đánh lấy máu
  # mới nhất, sau lượt đánh báo sát thương vừa gây.
  @strikes ~w(attack skill potion flee)

  defp run(s, %{battle: %{over: false} = b} = p, %{"act" => act} = cmd) when act in @strikes do
    cond do
      World.world_battle?(p) -> world_strike(s, p, cmd)
      key = b[:encounter][:shared] -> shared_strike(s, p, cmd, key)
      true -> Commands.run(p, cmd)
    end
  end

  # Thách đấu (đấu trường): đối thủ là bản sao chỉ số dựng từ database.
  defp run(s, p, %{"act" => "pvp_challenge"} = cmd) do
    with nil <- p.battle && {:error, "Đang trong trận đấu."},
         true <- p.hp > 0 || {:error, "Bạn cần hồi máu trước."},
         {:ok, m} <- Arena.challenge(s.user_id, cmd["uid"]) do
      {r, p2} = Engine.start_with_monster(p, 1, m)
      enc = %{pvp: m.pvp, hp: p.hp, gold: p.gold, deaths: p.deaths}
      {Map.put(r, :msg, "Thách đấu #{m.name}!"), put_in(p2.battle[:encounter], enc)}
    else
      {:error, msg} -> {%{ok: false, msg: msg}, p}
    end
  end

  defp run(_s, p, cmd), do: Commands.run(p, cmd)

  defp world_strike(s, p, cmd) do
    case WorldBoss.hp() do
      nil ->
        {%{ok: true}, end_world_battle(p, "fled", "#{WorldBoss.name()} đã rời khỏi Tế Đàn.")}

      hp ->
        p = put_in(p.battle.monster.hp, hp)
        {result, p2} = Commands.run(p, cmd)
        dealt = if p2.battle, do: hp - p2.battle.monster.hp, else: 0

        case dealt > 0 && WorldBoss.hit(s.user_id, p.name, dealt) do
          false ->
            {result, p2}

          {:alive, left} ->
            {result, put_in(p2.battle.monster.hp, left)}

          :killed ->
            p2 = put_in(p2.battle.monster.hp, 0)

            # người khác vừa đánh trước nên máu chung hết sớm hơn máu mình thấy
            if p2.battle.over,
              do: {result, p2},
              else:
                {%{ok: true, result: "win"},
                 end_world_battle(p2, "win", "🏆 #{WorldBoss.name()} gục ngã dưới đòn của bạn!")}

          :gone ->
            {%{ok: true},
             end_world_battle(p2, "win", "#{WorldBoss.name()} đã bị người khác hạ gục.")}
        end
    end
  end

  # Trận đánh chung với tổ đội: máu quái ở HacLong.Party, thưởng chia theo số người.
  defp shared_strike(s, p, cmd, key) do
    case Party.fight(key) do
      # không có tổ đội hoặc mọi người khác đã rời: đánh như thường
      nil ->
        Commands.run(p, cmd)

      f ->
        p = p |> put_in([:battle, :monster, :hp], f.hp) |> shared_reward(f)
        {result, p2} = Commands.run(p, cmd)
        dealt = if p2.battle, do: f.hp - p2.battle.monster.hp, else: 0

        case dealt > 0 && Party.hit(key, s.user_id, dealt) do
          false ->
            {result, p2}

          {:alive, left} ->
            {result, put_in(p2.battle.monster.hp, left)}

          {:killed, _n} ->
            if p2.battle.over, do: {result, p2}, else: shared_win(p2)

          # đồng đội vừa hạ trước
          :gone ->
            shared_win(p2)
        end
    end
  end

  defp shared_win(p) do
    {r, p} = Engine.finish_win(p)
    {Map.put(r, :result, "win"), p}
  end

  # thưởng mỗi người = thưởng gốc × 1,2 / số người (một người thì giữ nguyên)
  defp shared_reward(p, %{n: n, xp: xp, gold: gold}) when n > 1 do
    k = 1.2 / n

    p
    |> put_in([:battle, :monster, :xp], round(xp * k))
    |> put_in([:battle, :monster, :gold], round(gold * k))
  end

  defp shared_reward(p, _), do: p

  defp end_world_battle(%{battle: %{over: false}} = p, result, text) do
    b = p.battle
    b = if result == "win", do: put_in(b.monster.hp, 0), else: b
    entry = %{text: text, kind: if(result == "win", do: "win", else: "info")}
    %{p | battle: %{b | over: true, result: result, log: Enum.take(b.log ++ [entry], -60)}}
  end

  defp end_world_battle(p, _result, _text), do: p

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _}, s) do
    s = %{s | tabs: Map.delete(s.tabs, ref)}

    if map_size(s.tabs) == 0 do
      World.leave(s.player, s.user_id)
      {:noreply, flush(s), @idle_timeout}
    else
      {:noreply, s}
    end
  end

  def handle_info(:flush, s), do: {:noreply, flush(%{s | flush_timer: nil}), timeout(s)}

  def handle_info(:timeout, s) do
    if map_size(s.tabs) == 0, do: {:stop, :normal, flush(s)}, else: {:noreply, s}
  end

  def handle_info({:EXIT, _pid, _reason}, s), do: {:noreply, s, timeout(s)}

  @impl true
  def terminate(_reason, s), do: flush(s)

  # ---------- Nội bộ ----------

  defp reply(value, s), do: {:reply, value, s, timeout(s)}

  # Còn tab đang mở thì không tự tắt (nhân vật vẫn đứng trên bản đồ).
  defp timeout(%{tabs: tabs}) when map_size(tabs) > 0, do: :infinity
  defp timeout(_), do: @idle_timeout

  defp run_move(%{player: nil} = s, _cmd), do: {%{ok: false, msg: "Chưa có nhân vật."}, s.player}

  defp run_move(s, %{"act" => "teleport"} = cmd),
    do: World.teleport(s.player, s.user_id, cmd["to"])

  defp run_move(s, cmd),
    do: World.move(s.player, s.user_id, cmd["dir"], cmd["confirm"] == true)

  defp after_command(s, old, player, cmd) do
    cond do
      # trận vừa kết thúc: cập nhật quái trên bản đồ, gục ngã thì về Nhà
      player && old && old.battle && not old.battle.over && player.battle && player.battle.over ->
        battle_over(s, old, player)

      cmd["act"] == "create" and player && old == nil ->
        if map_size(s.tabs) > 0, do: World.enter(player, s.user_id)
        player

      # vừa vào tháp: rời bản đồ Làng (người khác không thấy mình nữa)
      old && player && player.pos.map == Tower.map_id() && old.pos.map != Tower.map_id() ->
        World.leave(old, s.user_id)
        player

      cmd["act"] == "reset" and old && player == nil ->
        World.leave(old, s.user_id)
        player

      true ->
        player
    end
  end

  # Trận đấu trường xong: đổi điểm; thua thì không mất gì (máu, vàng như trước trận).
  defp battle_over(s, _old, %{battle: %{encounter: %{pvp: target} = enc} = b} = player) do
    r = Arena.finish(s.user_id, target, b.result)

    player =
      if r.won,
        do: %{player | gold: player.gold + r.gold},
        else: %{player | hp: max(1, enc.hp), gold: enc.gold, deaths: enc.deaths}

    sign = fn d -> if d >= 0, do: "+#{d}", else: "#{d}" end

    text =
      if r.won,
        do: "🏟 Thắng! Điểm đấu trường #{sign.(r.delta)}, thưởng #{r.gold} vàng.",
        else: "🏟 Thua trận đấu trường (điểm #{sign.(r.delta)}). Không mất vàng."

    reward = %{xp: 0, gold: r.gold, items: [], levels: 0}

    player = %{
      player
      | battle: %{b | reward: reward, log: Enum.take(b.log ++ [%{text: text, kind: "win"}], -60)}
    }

    Phoenix.PubSub.broadcast(
      HacLong.PubSub,
      topic(target),
      {:notice,
       "🏟 #{player.name} thách đấu bạn ở đấu trường và #{if r.won, do: "thắng", else: "thua"} (điểm của bạn #{sign.(r.their_delta)})."}
    )

    player
  end

  # Trận vừa kết thúc: cập nhật quái trên bản đồ, gục ngã thì về Nhà, tính nhiệm vụ...
  defp battle_over(s, old, player) do
    player = player |> Tower.after_battle() |> World.finish_encounter(s.user_id)

    # lần đầu hạ Hắc Long: ghi lại thời điểm cho bảng xếp hạng
    player =
      if player.victory and not old.victory,
        do: Map.put(player, :victory_at, DateTime.truncate(DateTime.utc_now(), :second)),
        else: player

    if player.battle.result == "win" do
      player
      |> guild_xp()
      |> Quests.on_kill(player.battle.monster.id)
      |> Daily.on_kill(player.battle.monster.id, player.battle.zone)
    else
      player
    end
  end

  # Bang từ cấp 2: thêm kinh nghiệm mỗi trận thắng.
  defp guild_xp(%{guild: %{level: lv}} = p) when lv > 1 do
    bonus = round(p.battle.monster.xp * Guilds.xp_bonus(lv))

    if bonus > 0 do
      {_levels, p} = Engine.gain_xp(p, bonus)
      log = p.battle.log ++ [%{text: "Bang hội: +#{bonus} kinh nghiệm.", kind: "good"}]
      put_in(p.battle.log, Enum.take(log, -60))
    else
      p
    end
  end

  defp guild_xp(p), do: p

  # Xô token: mỗi `every_ms` hồi một lượt, tối đa `burst` lượt.
  defp take(s, key, every_ms, burst) do
    {tokens, at} = Map.fetch!(s, key)
    t = now()
    tokens = min(burst, tokens + (t - at) / every_ms)

    if tokens >= 1,
      do: {:ok, Map.put(s, key, {tokens - 1, t})},
      else: :too_fast
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp broadcast(s, player, origin) do
    Phoenix.PubSub.broadcast(HacLong.PubSub, topic(s.user_id), {:player, player, origin})
  end

  defp save(s, player) do
    Characters.save!(s.user_id, player)
    cancel_flush(%{s | player: player, dirty: false})
  end

  defp delete(s) do
    Characters.delete!(s.user_id)
    cancel_flush(%{s | player: nil, dirty: false})
  end

  defp mark_dirty(%{flush_timer: nil} = s),
    do: %{s | dirty: true, flush_timer: Process.send_after(self(), :flush, @flush_ms)}

  defp mark_dirty(s), do: %{s | dirty: true}

  defp cancel_flush(%{flush_timer: nil} = s), do: s

  defp cancel_flush(s) do
    Process.cancel_timer(s.flush_timer)
    %{s | flush_timer: nil}
  end

  defp flush(%{dirty: true, player: p} = s) when p != nil, do: save(s, p)
  defp flush(s), do: s
end
