locals {
  # Mesma senha usada no aws_db_instance e injetada na Lambda como env var.
  # Centralizado aqui para nao gerar duas random_password diferentes.
  db_password = coalesce(var.db_password, try(random_password.db[0].result, null))
}
