variable "name" { type = string }
variable "location" { type = string }
variable "resource_group" { type = string }
variable "sku" { type = string }
variable "tags" { type = map(string) }

resource "azurerm_container_registry" "main" {
  name                = substr("acr${var.name}", 0, 50)
  resource_group_name = var.resource_group
  location            = var.location
  sku                 = var.sku
  admin_enabled       = false
  tags                = var.tags
}

output "login_server" { value = azurerm_container_registry.main.login_server }
output "id" { value = azurerm_container_registry.main.id }
