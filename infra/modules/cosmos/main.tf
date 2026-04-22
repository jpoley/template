variable "name_prefix" { type = string }
variable "suffix" { type = string }
variable "location" { type = string }
variable "resource_group" { type = string }
variable "consistency_level" { type = string }
variable "throughput_mode" { type = string }
variable "provisioned_throughput" { type = number }
variable "tags" { type = map(string) }

locals {
  is_serverless = var.throughput_mode == "serverless"
}

resource "azurerm_cosmosdb_account" "main" {
  name                = "cosmos-${var.name_prefix}-${var.suffix}"
  location            = var.location
  resource_group_name = var.resource_group
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  consistency_policy {
    consistency_level = var.consistency_level
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }

  capabilities {
    name = local.is_serverless ? "EnableServerless" : "EnableNoSQL"
  }

  public_network_access_enabled = true
  tags                          = var.tags
}

resource "azurerm_cosmosdb_sql_database" "main" {
  name                = "projecttemplate"
  resource_group_name = var.resource_group
  account_name        = azurerm_cosmosdb_account.main.name
  throughput          = local.is_serverless ? null : var.provisioned_throughput
}

resource "azurerm_cosmosdb_sql_container" "items" {
  name                  = "items"
  resource_group_name   = var.resource_group
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_sql_database.main.name
  partition_key_paths   = ["/partitionKey"]
  partition_key_version = 2

  indexing_policy {
    indexing_mode = "consistent"
    included_path { path = "/*" }
    excluded_path { path = "/\"_etag\"/?" }
  }
}

output "endpoint" { value = azurerm_cosmosdb_account.main.endpoint }
output "account_id" { value = azurerm_cosmosdb_account.main.id }
output "account_name" { value = azurerm_cosmosdb_account.main.name }
output "database_name" { value = azurerm_cosmosdb_sql_database.main.name }
output "container_name" { value = azurerm_cosmosdb_sql_container.items.name }
