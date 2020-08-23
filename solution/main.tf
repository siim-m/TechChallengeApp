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

# Azure geo to deploy resources in
variable "location" {
  type = string
}

# Sku of Azure Container Registry – basic, standard or premium
variable "acr_sku" {
  type    = string
  default = "basic"
}

# Username of Postgres server
variable "postgres_user" {
  type = string
}

# Password of Postgres server
variable "postgres_password" {
  type = string
}

# Sku of Postgres server https://docs.microsoft.com/en-us/azure/postgresql/concepts-pricing-tiers
variable "postgres_server_sku" {
  type    = string
  default = "B_Gen5_1"
}

# Public IP address of the computer from which the deployment is run.
# This will be whitelisted on the Postgres server to allow seeding the database.
variable "local_public_ip" {
  type = string
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
  admin_enabled       = true

  # Local provisioner builds the Docker image and pushes it to ACR
  provisioner "local-exec" {
    working_dir = ".."
    command     = <<EOT
      az acr login --name ${self.name}
      docker build . -t techchallengeapp:latest
      docker tag techchallengeapp ${self.login_server}/techchallengeapp:latest
      docker push ${self.login_server}/techchallengeapp:latest
EOT
  }
}

resource "azurerm_container_group" "cg" {
  name                = "${var.prefix}${random_integer.random.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_address_type     = "public"
  dns_name_label      = "${var.prefix}${random_integer.random.result}"
  os_type             = "Linux"

  image_registry_credential {
    username = azurerm_container_registry.acr.admin_username
    password = azurerm_container_registry.acr.admin_password
    server   = azurerm_container_registry.acr.login_server
  }

  container {
    name   = "techchallengeapp"
    image  = "${azurerm_container_registry.acr.login_server}/techchallengeapp:latest"
    cpu    = "1"
    memory = "1"

    commands = ["./TechChallengeApp", "serve"]

    # Container environment variables are used instead of conf.toml file
    environment_variables = {
      "VTT_DBHOST"     = azurerm_postgresql_server.pgsrv.fqdn
      "VTT_DBNAME"     = azurerm_postgresql_database.pgdb.name
      "VTT_DBPORT"     = "5432"
      "VTT_DBUSER"     = "${var.postgres_user}@${azurerm_postgresql_server.pgsrv.name}"
      "VTT_LISTENHOST" = "0.0.0.0"
      "VTT_LISTENPORT" = "80"
    }

    secure_environment_variables = {
      "VTT_DBPASSWORD" = var.postgres_password
    }

    ports {
      port     = 80
      protocol = "TCP"
    }
  }
}


resource "azurerm_postgresql_server" "pgsrv" {
  name                = "${var.prefix}${random_integer.random.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  sku_name = var.postgres_server_sku

  storage_mb                   = 5120
  backup_retention_days        = 7
  geo_redundant_backup_enabled = false

  administrator_login          = var.postgres_user
  administrator_login_password = var.postgres_password
  version                      = "9.6"

  ssl_enforcement_enabled = false
}

# 0.0.0.0 represents Azure internal IP addresses.
resource "azurerm_postgresql_firewall_rule" "pgfw_azure" {
  name                = "azure"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_postgresql_server.pgsrv.name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "0.0.0.0"
}

# Whitelist public IP of local computer to allow preseeding of data in database.
resource "azurerm_postgresql_firewall_rule" "pgfw_local" {
  name                = "local"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_postgresql_server.pgsrv.name
  start_ip_address    = var.local_public_ip
  end_ip_address      = var.local_public_ip
}

resource "azurerm_postgresql_database" "pgdb" {
  name                = "${var.prefix}${random_integer.random.result}"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_postgresql_server.pgsrv.name
  charset             = "UTF8"
  collation           = "English_United States.1252"

  # Explicit dependency to make sure data seeding does not run before the firewall rule is in place.
  depends_on = [
    azurerm_postgresql_firewall_rule.pgfw_local
  ]

  # Provisioner runs the container locally to seed the database with data.
  provisioner "local-exec" {
    working_dir = ".."
    command     = <<EOT
      docker run -e VTT_DBUSER=$DBUSER -e VTT_DBPASSWORD=$DBPASSWORD -e VTT_DBHOST=$DBHOST -e VTT_DBNAME=$DBNAME -e VTT_DBPORT=$DBPORT techchallengeapp updatedb -s
EOT

    environment = {
      DBPASSWORD = var.postgres_password
      DBUSER     = "${var.postgres_user}@${azurerm_postgresql_server.pgsrv.name}"
      DBHOST     = azurerm_postgresql_server.pgsrv.fqdn
      DBNAME     = self.name
      DBPORT     = "5432"
    }
  }
}

output "application_url" {
  value = "http://${azurerm_container_group.cg.fqdn}"
}
