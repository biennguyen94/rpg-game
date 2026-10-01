defmodule HacLong.Repo.Migrations.CreateMarketListings do
  use Ecto.Migration

  def change do
    # hàng rao bán ở chợ: đồ thường (`item`, `count`) hoặc một món đồ chỉ số ngẫu nhiên (`gear`)
    create table(:market_listings) do
      add :seller_id, references(:users, on_delete: :delete_all), null: false
      add :item, :string
      add :count, :integer, null: false, default: 1
      add :gear, :map
      add :price, :integer, null: false
      add :buyer_id, references(:users, on_delete: :nilify_all)
      add :sold_at, :utc_datetime
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:market_listings, [:sold_at, :inserted_at])
    create index(:market_listings, [:seller_id])
  end
end
