##### INITIALISE AZURE PROVIDER #####

provider "azurerm" {
  version = "=2.23.0"
  features {}
}

##### VARIABLE DEFINITIONS #####

# Name prefix for resources
variable "prefix" {
  type = string
}

variable "location" {
  type = string
}

variable "acr_sku" {
  type    = string
  default = "basic"
}

##### RESOURCES #####

# Using a random integer in resource names provides reasonable certainty that
# resource names are unique (only required for certain resource types).

resource "random_integer" "random" {
  min = 10000
  max = 99999
}

resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}${random_integer.random.result}"
  location = var.location
}

resource "azurerm_container_registry" "acr" {
  name                = "${var.prefix}${random_integer.random.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = var.acr_sku
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.prefix}${random_integer.random.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "${var.prefix}${random_integer.random.result}"

  default_node_pool {
    name       = "default"
    node_count = 2
    vm_size    = "Standard_D2_v2"
  }

  identity {
    type = "SystemAssigned"
  }
}

# RBAC role to allow AKS to connect to ACR using its Managed Identity

resource "azurerm_role_assignment" "acrpull" {
  scope                = azurerm_container_registry.acr.id
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id
  role_definition_name = "acrpull"
}
