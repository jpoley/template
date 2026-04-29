output "resource_group" {
  value = azurerm_resource_group.main.name
}

output "container_registry" {
  value = module.registry.login_server
}

output "postgres_fqdn" {
  value = module.postgres.fqdn
}

output "frontend_url" {
  value = module.frontdoor.frontend_url
}

output "internal_url" {
  value = module.frontdoor.internal_url
}

output "backend_url" {
  value = module.frontdoor.backend_url
}

output "app_insights_connection_string" {
  value     = module.observability.app_insights_connection_string
  sensitive = true
}
