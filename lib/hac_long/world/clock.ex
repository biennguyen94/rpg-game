defmodule HacLong.World.Clock do
  @moduledoc """
  Ngày và đêm theo giờ thật (giờ Việt Nam).

  - `"dawn"` 5–7 giờ, `"day"` 7–18 giờ, `"dusk"` 18–20 giờ, `"night"` 20–5 giờ.
  - Ban đêm quái mới sinh ra có thể là quái Bóng Đêm (xem `HacLong.World.MapServer`).
  - Ép một buổi cố định (để thử) bằng `config :hac_long, :time_of_day, "night"` hoặc biến
    môi trường `TIME_OF_DAY`.
  """

  @utc_offset 7 * 3600
  @phases ~w(dawn day dusk night)

  def hour(now \\ DateTime.utc_now()) do
    local = DateTime.add(now, @utc_offset, :second)
    local.hour + local.minute / 60
  end

  def phase(now \\ DateTime.utc_now()) do
    case Application.get_env(:hac_long, :time_of_day) do
      forced when forced in @phases ->
        forced

      _ ->
        h = hour(now)

        cond do
          h >= 5 and h < 7 -> "dawn"
          h >= 7 and h < 18 -> "day"
          h >= 18 and h < 20 -> "dusk"
          true -> "night"
        end
    end
  end

  def night?(now \\ DateTime.utc_now()), do: phase(now) == "night"
end
