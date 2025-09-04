defmodule Ochat2.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:messages) do
      add :body, :string
      add :who, :string
      add :conversation_id, references(:conversations, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:messages, [:conversation_id])
  end
end
