# Solution – TechChallengeApp

This solution uses Terraform to deploy a containerised version of the application
to Azure Container Instances with an Azure PostgreSQL database. It also uses Azure
Container Registry for storing the container image.

As the grading criteria called for simplicity and the ability to start from a cloned
Git repo, I decided to use Terraform's *local-exec* provisioner to build the container
image, push it to ACR, and to run the image locally for preseeding the database.
I considered using Azure Pipelines or GitHub Actions to create a CI/CD pipeline
for build and deployment tasks, but decided it would probably be too complex for
a simple deployment.

Additional comments are provided in the `solution/main.tf` file.

## Prerequisites

The following tools need to be installed on the machine from which the deployment
is run. It was developed and tested on macOS Catalina in the zsh shell.

- Terraform (tested using v0.12.28)
- Docker (tested using v19.03.12)
- Azure CLI (tested using v2.10.1)

You will also need an active Azure subscription and at least Contributor access.

## Instructions

- Clone the repository to your local machine.
- In the *solution/* directory, create a *terraform.tfvars* file and define your
  variables.

  The *local_public_ip* variable is required to allow connectivity from your local
  machine to the database for preseeding.

  ⚠️ **Note: spaces (and potentially some other special characters?) in the Postgres
  password will cause the preseeding to fail.**

  Example:

  ```text
  prefix              = "techchallenge"
  location            = "australiaeast"
  acr_sku             = "basic"
  postgres_user       = "pgadmin"
  postgres_password   = "changeme"
  postgres_server_sku = "B_Gen5_1"
  local_public_ip     = "167.179.157.35"
  ```
  
- Run `az login` to log in to Azure using Azure CLI.
- Select the appropriate subscription: `az account set -s <subscription name>`.
- Ensure you are in the *solution/* directory.
- Initialise the Terraform providers: `terraform init`
- Run and inspect the Terraform plan: `terraform plan -out plan.tfplan`
- If all looks OK, deploy the solution: `terraform apply plan.tfplan`
- The command will take a couple of minutes to run. When ready, it will output
  the URL to the application.
- When done, clean up the resources: `terraform destroy`

## Potential Improvements

- Currently, the ACR admin credentials are used for deploying the container to ACI.
  In a Production environment, it would make more sense to use an Azure AD Service
  Principal.
- While ACI ensures that a host machine is always available and will restart the
  container on a healthy host if one fails, there is no application-level HA or
  load balancing. This could be achieved in a number of ways, such as:
  
  - Deploying multiple container instances (potentially in different geographies)
    and configuring a load-balancer or application gateway.
  - Using a container orchestration solution, such as AKS.
  - Running containers on Virtual Machines in an Availability Set and having an
    Azure Load Balancer in front.
