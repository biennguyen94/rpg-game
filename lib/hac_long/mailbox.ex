defmodule HacLong.Mailbox do
  @moduledoc """
  Hộp thư: thư hệ thống gửi cho người chơi, có thể kèm quà (vàng, kinh nghiệm, đồ).

  - Dùng để báo thưởng nhận lúc vắng mặt (trùm thế giới) và cho quản trị viên tặng quà.
  - Mở thư là nhận quà luôn (`claim/3`); thư không có quà thì mở là đánh dấu đã đọc.
  - Nhận quà trong một transaction cùng lần ghi nhân vật: đánh dấu thư đã nhận chỉ thành
    công một lần (`claimed_at IS NULL`), nên bấm hai lần hay hai tab cùng bấm cũng không
    nhận đôi.
  - Gửi thư thì báo số thư chưa mở qua PubSub (`{:mail, số}` trên kênh của người chơi).
  - Giữ tối đa `@keep` thư mới nhất mỗi người; thư cũ đã mở bị xóa.
  """
  import Ecto.Query

  alias HacLong.Repo
  alias HacLong.Game.{Character, Data, Engine}

  @keep 50

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  @doc """
  Gửi thư. `attrs`: `subject` (bắt buộc), `body`, `gold`, `xp`, `items` (`%{id => số}`).
  """
  def send(user_id, attrs) do
    with {:ok, row} <- row(attrs) do
      Repo.insert_all("mails", [Map.put(row, :user_id, user_id)])
      notify(user_id)
      :ok
    end
  end

  @doc "Gửi cho mọi người đã có nhân vật. Trả về số thư đã gửi."
  def send_all(attrs) do
    with {:ok, row} <- row(attrs) do
      ids = Repo.all(from c in Character, select: c.user_id)
      rows = Enum.map(ids, &Map.put(row, :user_id, &1))
      rows |> Enum.chunk_every(1000) |> Enum.each(&Repo.insert_all("mails", &1))
      Enum.each(ids, &notify/1)
      {:ok, length(ids)}
    end
  end

  defp row(attrs) do
    a = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    subject = a["subject"] |> to_string() |> String.trim() |> String.slice(0, 80)
    gold = a["gold"] || 0
    xp = a["xp"] || 0
    items = a["items"] || %{}

    cond do
      subject == "" ->
        {:error, "Thư cần có tiêu đề."}

      not (is_integer(gold) and gold >= 0 and is_integer(xp) and xp >= 0) ->
        {:error, "Vàng và kinh nghiệm phải là số không âm."}

      not (is_map(items) and
               Enum.all?(items, fn {id, n} -> Data.item(id) && is_integer(n) && n > 0 end)) ->
        {:error, "Vật phẩm không hợp lệ."}

      true ->
        {:ok,
         %{
           subject: subject,
           body: a["body"] |> to_string() |> String.slice(0, 1000),
           gold: gold,
           xp: xp,
           items: items,
           inserted_at: now()
         }}
    end
  end

  @doc "Số thư chưa mở."
  def unread(user_id) do
    Repo.aggregate(
      from(m in "mails", where: m.user_id == ^user_id and is_nil(m.claimed_at)),
      :count
    )
  end

  @doc "Các thư gần nhất, mới trước."
  def list(user_id) do
    cleanup(user_id)

    Repo.all(
      from m in "mails",
        where: m.user_id == ^user_id,
        order_by: [desc: m.id],
        limit: @keep,
        select: %{
          id: m.id,
          subject: m.subject,
          body: m.body,
          gold: m.gold,
          xp: m.xp,
          items: m.items,
          claimed: not is_nil(m.claimed_at),
          at: m.inserted_at
        }
    )
  end

  # thư đã mở nằm ngoài @keep thư mới nhất thì xóa
  defp cleanup(user_id) do
    case Repo.one(
           from m in "mails",
             where: m.user_id == ^user_id,
             order_by: [desc: m.id],
             offset: ^(@keep - 1),
             limit: 1,
             select: m.id
         ) do
      nil ->
        :ok

      oldest ->
        Repo.delete_all(
          from m in "mails",
            where: m.user_id == ^user_id and m.id < ^oldest and not is_nil(m.claimed_at)
        )
    end
  end

  @doc """
  Mở thư `id` của `user_id` và trao quà cho nhân vật `p`. `save` được gọi với nhân vật mới
  trong cùng transaction (để ghi database). Trả về `{:ok, thông_báo, nhân_vật}` hoặc
  `{:error, lý_do}`.
  """
  def claim(user_id, id, p, save) when is_integer(id) do
    Repo.transaction(fn ->
      {n, rows} =
        Repo.update_all(
          from(m in "mails",
            where: m.id == ^id and m.user_id == ^user_id and is_nil(m.claimed_at),
            select: %{subject: m.subject, gold: m.gold, xp: m.xp, items: m.items}
          ),
          set: [claimed_at: now()]
        )

      if n == 0, do: Repo.rollback("Thư đã mở rồi.")
      mail = hd(rows)
      p = give(p, mail)
      save.(p)
      {describe(mail), p}
    end)
    |> case do
      {:ok, {msg, p}} ->
        notify(user_id)
        {:ok, msg, p}

      {:error, msg} ->
        {:error, msg}
    end
  end

  def claim(_user_id, _id, _p, _save), do: {:error, "Thư không hợp lệ."}

  defp give(p, mail) do
    p = %{p | gold: p.gold + mail.gold}

    p =
      Enum.reduce(mail.items, p, fn {id, n}, p ->
        if Data.item(id), do: Engine.add_item(p, id, n), else: p
      end)

    {_levels, p} = Engine.gain_xp(p, mail.xp)
    p
  end

  defp describe(%{gold: 0, xp: 0, items: items}) when map_size(items) == 0, do: "Đã đọc thư."

  defp describe(mail) do
    parts =
      [
        mail.gold > 0 && "+#{mail.gold} vàng",
        mail.xp > 0 && "+#{mail.xp} kinh nghiệm"
        | Enum.map(mail.items, fn {id, n} ->
            name = if it = Data.item(id), do: it.name, else: id
            if n > 1, do: "#{name} ×#{n}", else: name
          end)
      ]
      |> Enum.filter(& &1)

    "Nhận quà: " <> Enum.join(parts, ", ") <> "."
  end

  defp notify(user_id) do
    Phoenix.PubSub.broadcast(
      HacLong.PubSub,
      HacLong.Game.Session.topic(user_id),
      {:mail, unread(user_id)}
    )
  end
end
