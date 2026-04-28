output "resource_group" {
  value = azurerm_resource_group.main.name
}

output "container_registry" {
  value = module.registry.login_server
}

output "db_provider" {
  value = var.db_provider
}

output "db_fqdn" {
  description = "FQDN of the managed database, or empty when db_provider = none."
  value = (
    var.db_provider == "postgres" ? try(module.postgres[0].fqdn, "") :
    var.db_provider == "sqlserver" ? try(module.mssql[0].fqdn, "") :
    ""
  )
}

output "frontend_url" {
  description = "Public frontend URL — Front Door endpoint when enabled, otherwise the Container App ingress FQDN."
  value = (
    var.deploy_frontdoor
    ? try(module.frontdoor[0].frontend_url, "")
    : "https://${module.container_apps.frontend_fqdn}"
  )
}

output "admin_url" {
  description = "Public admin URL, or empty when deploy_admin = false."
  value = (
    !var.deploy_admin ? "" :
    var.deploy_frontdoor ? try(module.frontdoor[0].admin_url, "") :
    "https://${module.container_apps.admin_fqdn}"
  )
}

output "backend_url" {
  description = "Public backend URL — Front Door endpoint when enabled, otherwise the Container App ingress FQDN."
  value = (
    var.deploy_frontdoor
    ? try(module.frontdoor[0].backend_url, "")
    : "https://${module.container_apps.backend_fqdn}"
  )
}

output "app_insights_connection_string" {
  value     = module.observability.app_insights_connection_string
  sensitive = true
}
