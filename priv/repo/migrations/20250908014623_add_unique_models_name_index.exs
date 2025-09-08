defmodule Ochat2.Repo.Migrations.AddUniqueModelsNameIndex do
  use Ecto.Migration

  def change do
    create_if_not_exists unique_index("models", [:name])
  end
end
