variable "name_prefix" { type = string }
variable "resource_group" { type = string }
variable "sku" { type = string }
variable "backend_fqdn" { type = string }
variable "frontend_fqdn" { type = string }
variable "internal_fqdn" { type = string }
variable "custom_domain" { type = string }
variable "internal_allowed_ips" { type = list(string) }
variable "tags" { type = map(string) }

resource "azurerm_cdn_frontdoor_profile" "main" {
  name                = "afd-${var.name_prefix}"
  resource_group_name = var.resource_group
  sku_name            = var.sku
  tags                = var.tags
}

resource "azurerm_cdn_frontdoor_endpoint" "main" {
  name                     = "ep-${var.name_prefix}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  tags                     = var.tags
}

# --- origin groups ------------------------------------------------------
locals {
  origins = {
    frontend = var.frontend_fqdn
    internal = var.internal_fqdn
    backend  = var.backend_fqdn
  }
}

resource "azurerm_cdn_frontdoor_origin_group" "each" {
  for_each                 = local.origins
  name                     = "og-${each.key}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  session_affinity_enabled = false

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
  }

  health_probe {
    path                = each.key == "backend" ? "/api/health" : "/"
    protocol            = "Https"
    interval_in_seconds = 100
    request_type        = "HEAD"
  }
}

resource "azurerm_cdn_frontdoor_origin" "each" {
  for_each                       = local.origins
  name                           = "o-${each.key}"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.each[each.key].id
  enabled                        = true
  host_name                      = each.value
  origin_host_header             = each.value
  http_port                      = 80
  https_port                     = 443
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = true
}

# --- WAF (optional internal IP allowlist) -------------------------------
resource "azurerm_cdn_frontdoor_firewall_policy" "internal" {
  count               = length(var.internal_allowed_ips) > 0 ? 1 : 0
  name                = replace("waf${var.name_prefix}internal", "-", "")
  resource_group_name = var.resource_group
  sku_name            = var.sku
  enabled             = true
  mode                = "Prevention"

  custom_rule {
    name     = "AllowInternalIPs"
    enabled  = true
    priority = 100
    type     = "MatchRule"
    action   = "Allow"

    match_condition {
      match_variable     = "RemoteAddr"
      operator           = "IPMatch"
      negation_condition = false
      match_values       = var.internal_allowed_ips
    }
  }

  custom_rule {
    name     = "DenyOthers"
    enabled  = true
    priority = 200
    type     = "MatchRule"
    action   = "Block"

    match_condition {
      match_variable     = "RequestUri"
      operator           = "BeginsWith"
      negation_condition = false
      match_values       = ["/"]
    }
  }
}

resource "azurerm_cdn_frontdoor_security_policy" "internal" {
  count                    = length(var.internal_allowed_ips) > 0 ? 1 : 0
  name                     = "secp-${var.name_prefix}-internal"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.internal[0].id

      association {
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.main.id
        }
        patterns_to_match = ["/internal/*"]
      }
    }
  }
}

# --- routes -------------------------------------------------------------
resource "azurerm_cdn_frontdoor_route" "backend" {
  name                          = "r-api"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.main.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.each["backend"].id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.each["backend"].id]
  supported_protocols           = ["Http", "Https"]
  patterns_to_match             = ["/api/*"]
  forwarding_protocol           = "HttpsOnly"
  https_redirect_enabled        = true
  link_to_default_domain        = true
}

resource "azurerm_cdn_frontdoor_route" "internal" {
  name                          = "r-internal"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.main.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.each["internal"].id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.each["internal"].id]
  supported_protocols           = ["Http", "Https"]
  patterns_to_match             = ["/internal/*"]
  forwarding_protocol           = "HttpsOnly"
  https_redirect_enabled        = true
  link_to_default_domain        = true
}

resource "azurerm_cdn_frontdoor_route" "frontend" {
  name                          = "r-frontend"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.main.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.each["frontend"].id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.each["frontend"].id]
  supported_protocols           = ["Http", "Https"]
  patterns_to_match             = ["/*"]
  forwarding_protocol           = "HttpsOnly"
  https_redirect_enabled        = true
  link_to_default_domain        = true
}

output "frontend_url" {
  value = "https://${azurerm_cdn_frontdoor_endpoint.main.host_name}"
}
output "internal_url" {
  value = "https://${azurerm_cdn_frontdoor_endpoint.main.host_name}/internal"
}
output "backend_url" {
  value = "https://${azurerm_cdn_frontdoor_endpoint.main.host_name}/api"
}
