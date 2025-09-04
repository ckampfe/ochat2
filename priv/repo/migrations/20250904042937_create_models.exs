defmodule Ochat2.Repo.Migrations.CreateModels do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:models) do
      add :name, :string

      timestamps(type: :utc_datetime)
    end
  end
end
