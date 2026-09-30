defmodule HacLong.Game.Character do
  @moduledoc "Bảng `characters`: trạng thái nhân vật đã lưu của một tài khoản."
  use Ecto.Schema

  @fields ~w(name cls level xp gold hp points stats equip inv bosses kills deaths victory battle map_id x y waystones quests victory_at name_key daily tower tower_best tutorial upgrades fish_caught achievements title gear bestiary rebirths chest_day pet pets furniture decor pet_xp daily_done boss_top)a

  schema "characters" do
    belongs_to :user, HacLong.Accounts.User
    field :name, :string
    field :cls, :string
    field :level, :integer
    field :xp, :integer
    field :gold, :integer
    field :hp, :integer
    field :points, :integer
    field :stats, :map
    field :equip, :map
    field :inv, :map
    field :bosses, {:array, :string}
    field :kills, :integer
    field :deaths, :integer
    field :victory, :boolean
    field :battle, :map
    field :map_id, :string
    field :x, :integer
    field :y, :integer
    field :waystones, {:array, :string}
    field :quests, :map
    field :victory_at, :utc_datetime
    field :name_key, :string
    field :daily, :map
    field :tower, :map
    field :tower_best, :integer, default: 0
    field :tutorial, :integer
    field :upgrades, :map, default: %{}
    field :fish_caught, :integer, default: 0
    field :achievements, {:array, :string}, default: []
    field :title, :string
    field :gear, {:array, :map}, default: []
    field :bestiary, :map, default: %{}
    field :rebirths, :integer, default: 0
    field :chest_day, :string
    field :pet, :string
    field :pets, {:array, :string}, default: []
    field :furniture, :map, default: %{}
    field :decor, {:array, :map}, default: []
    field :pet_xp, :map, default: %{}
    field :daily_done, :integer, default: 0
    field :boss_top, :integer, default: 0
    timestamps(type: :utc_datetime)
  end

  def fields, do: @fields
end
