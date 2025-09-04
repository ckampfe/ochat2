defmodule Ochat2.Repo.Migrations.CreateModels do
  use Ecto.Migration

  def change do
    create table(:models) do
      add :name, :string

      timestamps(type: :utc_datetime)
    end
  end
end
