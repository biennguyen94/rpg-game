defmodule HacLongWeb.PageController do
  use HacLongWeb, :controller

  alias HacLong.Game.{Achievements, Data, Engine}
  alias HacLong.World.Maps

  @doc """
  Trả về `priv/static/index.html` kèm dữ liệu game (`window.GAME_DATA`) để giao diện
  vẽ danh sách vùng đất, cửa hàng, lớp nhân vật... Dữ liệu chỉ có một nguồn là
  `priv/game_data.json` trên server.
  """
  def index(conn, _params) do
    data = Jason.encode!(client_data(), escape: :html_safe)

    html =
      Application.app_dir(:hac_long, "priv/static/index.html")
      |> File.read!()
      |> String.replace("<!--GAME_DATA-->", "<script>window.GAME_DATA = #{data};</script>")

    conn |> put_resp_content_type("text/html") |> send_resp(200, html)
  end

  defp client_data do
    %{
      CLASSES: Data.classes(),
      ZONES: Data.zones(),
      ITEMS:
        Map.new(Data.items(), fn {id, it} -> {id, Map.put(it, :sell, Engine.sell_price(id))} end),
      SHOP: Data.shop(),
      RECIPES: Data.recipes(),
      QUESTS: Data.quests(),
      PETS: Data.pets(),
      FURNITURE: Data.furniture(),
      ACHIEVEMENTS: Achievements.client_data(),
      RULES: %{
        maxLevel: Engine.max_level(),
        pointsPerLevel: Engine.points_per_level(),
        gearBag: HacLong.Game.Gear.max_bag(),
        rebirthPoints: Engine.rebirth_points(),
        maxRebirths: Engine.max_rebirths(),
        guildCost: HacLong.Guilds.create_cost(),
        guildMinDonate: HacLong.Guilds.min_donate(),
        tameKills: HacLong.Game.Pets.tame_kills(),
        petMaxLevel: HacLong.Game.Pets.max_level(),
        petSkillLevel: HacLong.Game.Pets.skill_level()
      },
      WORLD: Maps.client_data()
    }
  end
end
