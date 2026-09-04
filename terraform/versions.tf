# Sin bloque backend: el estado queda local y .gitignore lo excluye. Este repositorio
# nunca se aplica contra una cuenta AWS real, asi que un backend remoto agregaria un
# bucket y una tabla de bloqueo que nadie usaria.
terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.6"
    }
  }
}
