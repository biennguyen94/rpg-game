defmodule HacLong.Game.Character do
  @moduledoc "Bảng `characters`: trạng thái nhân vật đã lưu của một tài khoản."
  use Ecto.Schema

  @fields ~w(name cls level xp gold hp points stats equip inv bosses kills deaths victory battle map_id x y waystones quests)a

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
    timestamps(type: :utc_datetime)
  end

  def fields, do: @fields
end
