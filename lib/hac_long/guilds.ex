defmodule HacLong.Guilds do
  @moduledoc """
  Bang hội.

  - Lập bang tốn `@create_cost` vàng (`create/5`); góp vàng vào quỹ (`donate/4`) làm bang lên
    cấp (tối đa 5). Hai việc này trừ vàng của nhân vật nên chạy trong transaction cùng lần
    ghi nhân vật (gọi từ `HacLong.Game.Session`).
  - Mỗi cấp: thêm 5 chỗ (10 + 5 × cấp) và thành viên được thêm 2% kinh nghiệm mỗi trận từ
    cấp 2 (`xp_bonus/1`).
  - Bang mở (`open`) thì vào ngay; bang đóng thì gửi đơn, bang chủ hoặc phó bang duyệt.
  - Vai trò: `leader` (bang chủ: làm được mọi việc, chuyển quyền, giải tán), `officer` (phó
    bang: duyệt đơn, đuổi thành viên thường, sửa thông báo), `member`.
  - Thay đổi thành viên thì báo cho Session của người đó (`HacLong.Game.Session.refresh_guild/1`)
    để cập nhật `guild` trong trạng thái nhân vật (không lưu trong bảng characters) và cho kênh
    game đổi kênh chat bang.
  """
  import Ecto.Query

  alias HacLong.Repo
  alias HacLong.Accounts.User
  alias HacLong.Game.{Character, Names}

  @create_cost 5000
  # quỹ cần để đạt cấp 1..5
  @levels [0, 10_000, 30_000, 70_000, 150_000]
  @min_donate 100

  def create_cost, do: @create_cost
  def levels, do: @levels
  def min_donate, do: @min_donate

  def level(fund), do: Enum.count(@levels, &(fund >= &1))
  def capacity(level), do: 10 + 5 * level
  def xp_bonus(level), do: 0.02 * (level - 1)

  @doc "Quỹ cần để lên cấp tiếp theo (nil nếu đã tối đa)."
  def next_fund(fund), do: Enum.find(@levels, &(&1 > fund))

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  def topic(guild_id), do: "guild:#{guild_id}"

  # ---------- Đọc ----------

  defp membership(uid) do
    Repo.one(
      from m in "guild_members",
        join: g in "guilds",
        on: g.id == m.guild_id,
        where: m.user_id == ^uid,
        select: %{id: g.id, name: g.name, tag: g.tag, fund: g.fund, role: m.role}
    )
  end

  @doc "Bang của người chơi, gắn vào trạng thái nhân vật: `%{id, name, tag, level, role}` hoặc nil."
  def brief(uid) do
    case membership(uid) do
      nil -> nil
      m -> %{id: m.id, name: m.name, tag: m.tag, level: level(m.fund), role: m.role}
    end
  end

  defp guild(gid) do
    Repo.one(
      from g in "guilds",
        where: g.id == ^gid,
        select: %{
          id: g.id,
          name: g.name,
          tag: g.tag,
          fund: g.fund,
          open: g.open,
          notice: g.notice,
          leader_id: g.leader_id
        }
    )
  end

  defp count_members(gid),
    do: Repo.aggregate(from(m in "guild_members", where: m.guild_id == ^gid), :count)

  def member_ids(gid),
    do: Repo.all(from m in "guild_members", where: m.guild_id == ^gid, select: m.user_id)

  @doc "Danh sách bang (tìm theo tên hoặc ký hiệu), quỹ nhiều trước."
  def list(q \\ "") do
    pattern = "%" <> String.replace(to_string(q), ~r/[%_\\\\]/, "") <> "%"

    from(g in "guilds",
      left_join: m in "guild_members",
      on: m.guild_id == g.id,
      where: ilike(g.name, ^pattern) or ilike(g.tag, ^pattern),
      group_by: g.id,
      order_by: [desc: g.fund, asc: g.id],
      limit: 30,
      select: %{
        id: g.id,
        name: g.name,
        tag: g.tag,
        fund: g.fund,
        open: g.open,
        members: count(m.user_id)
      }
    )
    |> Repo.all()
    |> Enum.map(&decorate/1)
  end

  defp decorate(g) do
    lv = level(g.fund)
    Map.merge(g, %{level: lv, capacity: capacity(lv)})
  end

  @doc "Bảng xếp hạng bang theo quỹ."
  def top(n \\ 10) do
    list()
    |> Enum.take(n)
    |> Enum.with_index(1)
    |> Enum.map(fn {g, i} -> Map.put(g, :rank, i) end)
  end

  @doc "Chi tiết bang cho thành viên `viewer` (có đơn xin vào nếu là bang chủ/phó bang)."
  def info(gid, viewer) do
    case guild(gid) do
      nil ->
        nil

      g ->
        members =
          Repo.all(
            from m in "guild_members",
              join: u in User,
              on: u.id == m.user_id,
              left_join: c in Character,
              on: c.user_id == m.user_id,
              where: m.guild_id == ^gid,
              select: %{
                id: m.user_id,
                name: coalesce(c.name, u.username),
                level: c.level,
                cls: c.cls,
                role: m.role,
                contributed: m.contributed
              }
          )
          |> Enum.sort_by(&{role_rank(&1.role), -&1.contributed})

        me = Enum.find(members, &(&1.id == viewer))
        staff? = me && me.role in ~w(leader officer)
        lv = level(g.fund)

        g
        |> Map.drop([:leader_id])
        |> Map.merge(%{
          level: lv,
          capacity: capacity(lv),
          next_fund: next_fund(g.fund),
          xp_bonus: xp_bonus(lv),
          members: members,
          role: me && me.role,
          requests: if(staff?, do: requests(gid), else: [])
        })
    end
  end

  defp role_rank("leader"), do: 0
  defp role_rank("officer"), do: 1
  defp role_rank(_), do: 2

  defp requests(gid) do
    Repo.all(
      from r in "guild_requests",
        join: u in User,
        on: u.id == r.user_id,
        left_join: c in Character,
        on: c.user_id == r.user_id,
        where: r.guild_id == ^gid,
        order_by: r.inserted_at,
        select: %{id: r.user_id, name: coalesce(c.name, u.username), level: c.level, cls: c.cls}
    )
  end

  @doc "Các bang người chơi đã gửi đơn xin vào."
  def my_requests(uid),
    do: Repo.all(from r in "guild_requests", where: r.user_id == ^uid, select: r.guild_id)

  # ---------- Lập bang, góp quỹ (trừ vàng) ----------

  defp validate_name(name) do
    name = Names.normalize(name)
    len = String.length(name)

    cond do
      len < 3 or len > 20 ->
        {:error, "Tên bang phải dài 3–20 ký tự."}

      not Regex.match?(~r/^[\p{L}\p{M}\p{N} _\-]+$/u, name) ->
        {:error, "Tên bang chỉ gồm chữ, số, khoảng trắng, - và _."}

      true ->
        {:ok, name}
    end
  end

  defp validate_tag(tag) do
    tag = tag |> to_string() |> String.trim() |> String.upcase()

    if Regex.match?(~r/^[A-Z0-9]{2,4}$/, tag),
      do: {:ok, tag},
      else: {:error, "Ký hiệu bang gồm 2–4 chữ cái không dấu hoặc số."}
  end

  @doc """
  Lập bang. `save` ghi nhân vật (đã trừ vàng) trong cùng transaction.
  Trả về `{:ok, thông_báo, nhân_vật}` hoặc `{:error, lý_do}`.
  """
  def create(uid, name, tag, p, save) do
    with {:ok, name} <- validate_name(name),
         {:ok, tag} <- validate_tag(tag),
         nil <- membership(uid) && {:error, "Bạn đang ở trong một bang rồi."},
         true <- p.gold >= @create_cost || {:error, "Cần #{@create_cost} vàng để lập bang."},
         false <- taken?(name, tag) do
      Repo.transaction(fn ->
        {1, [%{id: gid}]} =
          Repo.insert_all(
            "guilds",
            [
              %{
                name: name,
                name_key: Names.key(name),
                tag: tag,
                leader_id: uid,
                inserted_at: now()
              }
            ],
            returning: [:id]
          )

        Repo.insert_all("guild_members", [
          %{user_id: uid, guild_id: gid, role: "leader", inserted_at: now()}
        ])

        Repo.delete_all(from r in "guild_requests", where: r.user_id == ^uid)
        p = %{p | gold: p.gold - @create_cost}
        save.(p)
        p
      end)
      |> case do
        {:ok, p} ->
          notify(uid)
          {:ok, "Đã lập bang #{name} [#{tag}]!", p}

        {:error, msg} ->
          {:error, msg}
      end
    else
      true -> {:error, "Tên hoặc ký hiệu bang đã có người dùng."}
      {:error, msg} -> {:error, msg}
    end
  rescue
    # hai người lập cùng tên đúng lúc: ràng buộc duy nhất chặn người sau
    Postgrex.Error -> {:error, "Tên hoặc ký hiệu bang đã có người dùng."}
  end

  defp taken?(name, tag) do
    Repo.exists?(from g in "guilds", where: g.name_key == ^Names.key(name) or g.tag == ^tag)
  end

  @doc "Góp `amount` vàng vào quỹ bang. Trả về `{:ok, thông_báo, nhân_vật}` hoặc `{:error, lý_do}`."
  def donate(uid, amount, p, save) do
    m = membership(uid)

    cond do
      m == nil ->
        {:error, "Bạn chưa vào bang nào."}

      not (is_integer(amount) and amount >= @min_donate) ->
        {:error, "Góp ít nhất #{@min_donate} vàng."}

      p.gold < amount ->
        {:error, "Không đủ vàng."}

      true ->
        {:ok, p} =
          Repo.transaction(fn ->
            Repo.update_all(from(g in "guilds", where: g.id == ^m.id), inc: [fund: amount])

            Repo.update_all(from(x in "guild_members", where: x.user_id == ^uid),
              inc: [contributed: amount]
            )

            p = %{p | gold: p.gold - amount}
            save.(p)
            p
          end)

        before = level(m.fund)
        after_ = level(m.fund + amount)

        if after_ > before do
          Enum.each(member_ids(m.id), &notify/1)

          system(
            m.id,
            "🎉 Bang lên cấp #{after_}! Thêm chỗ cho thành viên và kinh nghiệm mỗi trận."
          )
        end

        {:ok, "Đã góp #{amount} vàng vào quỹ bang.", p}
    end
  end

  # ---------- Thành viên ----------

  defp role_in(uid, gid) do
    Repo.one(
      from m in "guild_members",
        where: m.user_id == ^uid and m.guild_id == ^gid,
        select: m.role
    )
  end

  def join(uid, gid) do
    g = is_integer(gid) && guild(gid)

    cond do
      !g ->
        {:error, "Không có bang này."}

      membership(uid) ->
        {:error, "Bạn đang ở trong một bang rồi."}

      g.open and count_members(gid) >= capacity(level(g.fund)) ->
        {:error, "Bang đã đủ người."}

      g.open ->
        add_member(uid, gid)
        system(gid, "#{name_of(uid)} đã vào bang.")
        {:ok, "Đã vào bang #{g.name}."}

      true ->
        Repo.insert_all("guild_requests", [%{user_id: uid, guild_id: gid, inserted_at: now()}],
          on_conflict: :nothing
        )

        {:ok, "Đã gửi đơn xin vào #{g.name}. Chờ bang chủ duyệt."}
    end
  end

  def cancel_request(uid, gid) do
    Repo.delete_all(from r in "guild_requests", where: r.user_id == ^uid and r.guild_id == ^gid)
    {:ok, "Đã rút đơn."}
  end

  defp add_member(uid, gid) do
    Repo.transaction(fn ->
      Repo.insert_all("guild_members", [
        %{user_id: uid, guild_id: gid, role: "member", inserted_at: now()}
      ])

      Repo.delete_all(from r in "guild_requests", where: r.user_id == ^uid)
    end)

    notify(uid)
  end

  defp staff(actor) do
    case membership(actor) do
      %{role: r} = m when r in ~w(leader officer) -> {:ok, m}
      _ -> {:error, "Chỉ bang chủ hoặc phó bang làm được."}
    end
  end

  defp leader(actor) do
    case membership(actor) do
      %{role: "leader"} = m -> {:ok, m}
      _ -> {:error, "Chỉ bang chủ làm được."}
    end
  end

  def accept(actor, target) do
    with {:ok, m} <- staff(actor) do
      pending? =
        Repo.exists?(
          from r in "guild_requests", where: r.user_id == ^target and r.guild_id == ^m.id
        )

      cond do
        not pending? ->
          {:error, "Không còn đơn này."}

        membership(target) ->
          cancel_request(target, m.id)
          {:error, "Người này đã vào bang khác."}

        count_members(m.id) >= capacity(level(m.fund)) ->
          {:error, "Bang đã đủ người."}

        true ->
          add_member(target, m.id)
          system(m.id, "#{name_of(target)} đã vào bang.")
          {:ok, "Đã nhận #{name_of(target)}."}
      end
    end
  end

  def reject(actor, target) do
    with {:ok, m} <- staff(actor) do
      cancel_request(target, m.id)
      {:ok, "Đã từ chối."}
    end
  end

  def leave(uid) do
    case membership(uid) do
      nil ->
        {:error, "Bạn chưa vào bang nào."}

      %{role: "leader", id: gid} ->
        if count_members(gid) > 1,
          do: {:error, "Chuyển quyền bang chủ cho người khác trước khi rời bang."},
          else: disband(uid)

      %{id: gid} ->
        remove(uid, gid)
        system(gid, "#{name_of(uid)} đã rời bang.")
        {:ok, "Đã rời bang."}
    end
  end

  defp remove(uid, gid) do
    Repo.delete_all(from m in "guild_members", where: m.user_id == ^uid and m.guild_id == ^gid)
    notify(uid)
  end

  def kick(actor, target) do
    with {:ok, m} <- staff(actor) do
      case role_in(target, m.id) do
        nil ->
          {:error, "Người này không ở trong bang."}

        _ when target == actor ->
          {:error, "Không tự đuổi mình được."}

        "leader" ->
          {:error, "Không đuổi được bang chủ."}

        "officer" when m.role != "leader" ->
          {:error, "Chỉ bang chủ đuổi được phó bang."}

        _ ->
          remove(target, m.id)
          system(m.id, "#{name_of(target)} đã bị mời ra khỏi bang.")
          {:ok, "Đã đuổi #{name_of(target)}."}
      end
    end
  end

  @doc "Bang chủ đổi vai trò thành viên: `officer` (phó bang) hoặc `member`."
  def set_role(actor, target, role) when role in ~w(officer member) do
    with {:ok, m} <- leader(actor) do
      case role_in(target, m.id) do
        r when r in ~w(officer member) ->
          Repo.update_all(from(x in "guild_members", where: x.user_id == ^target),
            set: [role: role]
          )

          notify(target)
          {:ok, if(role == "officer", do: "Đã phong phó bang.", else: "Đã bỏ chức phó bang.")}

        _ ->
          {:error, "Người này không ở trong bang."}
      end
    end
  end

  def set_role(_, _, _), do: {:error, "Vai trò không hợp lệ."}

  def transfer(actor, target) do
    with {:ok, m} <- leader(actor) do
      if target != actor and role_in(target, m.id) do
        Repo.transaction(fn ->
          Repo.update_all(from(x in "guild_members", where: x.user_id == ^target),
            set: [role: "leader"]
          )

          Repo.update_all(from(x in "guild_members", where: x.user_id == ^actor),
            set: [role: "officer"]
          )

          Repo.update_all(from(g in "guilds", where: g.id == ^m.id), set: [leader_id: target])
        end)

        notify(actor)
        notify(target)
        system(m.id, "#{name_of(target)} trở thành bang chủ.")
        {:ok, "Đã chuyển quyền bang chủ."}
      else
        {:error, "Người này không ở trong bang."}
      end
    end
  end

  def disband(actor) do
    with {:ok, m} <- leader(actor) do
      ids = member_ids(m.id)
      Repo.delete_all(from g in "guilds", where: g.id == ^m.id)
      Enum.each(ids, &notify/1)
      {:ok, "Đã giải tán bang #{m.name}."}
    end
  end

  @doc "Bang chủ/phó bang đổi `open` (vào tự do hay phải xin) và `notice` (thông báo bang)."
  def settings(actor, attrs) do
    with {:ok, m} <- staff(actor) do
      set =
        [
          is_boolean(attrs["open"]) && {:open, attrs["open"]},
          is_binary(attrs["notice"]) &&
            {:notice, attrs["notice"] |> String.trim() |> String.slice(0, 120)}
        ]
        |> Enum.filter(& &1)

      if set != [], do: Repo.update_all(from(g in "guilds", where: g.id == ^m.id), set: set)
      {:ok, "Đã lưu."}
    end
  end

  # ---------- Thông báo ----------

  defp name_of(uid) do
    Repo.one(
      from u in User,
        left_join: c in Character,
        on: c.user_id == u.id,
        where: u.id == ^uid,
        select: coalesce(c.name, u.username)
    )
  end

  @doc "Tin hệ thống trong kênh chat bang."
  def system(gid, text) do
    msg = %{
      id: nil,
      uid: 0,
      name: "Bang hội",
      text: text,
      at: System.system_time(:millisecond),
      guild: true
    }

    Phoenix.PubSub.broadcast(HacLong.PubSub, topic(gid), {:guild_chat, msg})
  end

  # Báo Session (nếu đang chạy) cập nhật bang trong trạng thái nhân vật.
  defp notify(uid), do: HacLong.Game.Session.refresh_guild(uid)
end
