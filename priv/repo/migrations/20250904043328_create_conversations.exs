defmodule Ochat2.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:conversations) do
      add :name, :string
      add :model_id, references(:models, on_delete: :nothing)
      add :source_conversation_id, references(:conversations, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:conversations, [:model_id])
    create index(:conversations, [:source_conversation_id])
  end
end
