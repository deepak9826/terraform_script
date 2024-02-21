terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "1.31.1"
    }
  
  }
}
provider "databricks" {
 host = "https://adb-1870400807420647.7.azuredatabricks.net"  #replace with your databricks host name
 token = "dapi7b82275cec8824f30898d0e0412fb648-3"  #replace with token
}
provider "azurerm" {
  features {
    
  }
}

// initialize provider in normal mode


resource "azurerm_resource_group" "example" {
  name     = "resource_g" #replace according your choice
  location = "East US" # Change to your preferred Azure region
}

resource "azurerm_databricks_workspace" "example" {
  name                = "databricks-testing-workspace" #replace according your choice
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  sku                 = "premium"

  tags = {
    Environment = "Production"
  }
}




resource "azurerm_role_assignment" "example" {
 principal_id         = "37537613-8f3b-430b-b7ab-5a8e8a12dc80" # User or service principal Object ID
  role_definition_name = "Owner"
  scope                = azurerm_resource_group.example.id
}
resource "azurerm_storage_account" "unity_catalog" {
  name                = "azurestorageunity"  #replace according your choice
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  # tags                     = data.azurerm_resource_group.this.tags
  account_tier             = "Standard"
  account_replication_type = "GRS"
  is_hns_enabled           = true
}

resource "azurerm_storage_container" "unity_catalog" {
  name                  = "new-container" #replace according your choice
  storage_account_name  = azurerm_storage_account.unity_catalog.name
  container_access_type = "private"
}

resource "azurerm_role_assignment" "this" {
  scope                = azurerm_storage_account.unity_catalog.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_access_connector.example.identity[0].principal_id
  depends_on           = [azurerm_databricks_access_connector.example]
}

resource "azurerm_databricks_access_connector" "example" {
  name                = "databricks_access_container" #replace according your choice
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  identity {
    type = "SystemAssigned"
  }
}

resource "databricks_metastore" "this" {
  # provider = databricks.accounts
  name     = "demo_metastore"
  storage_root = format("abfss://%s@%s.dfs.core.windows.net",
    azurerm_storage_container.unity_catalog.name,
  azurerm_storage_account.unity_catalog.name)
  force_destroy = true
  region        = azurerm_resource_group.example.location
  
}

resource "databricks_metastore_assignment" "this" {
  # provider             = databricks.accounts
  workspace_id         = azurerm_databricks_workspace.example.workspace_id #replace 
  metastore_id         = databricks_metastore.this.id
  default_catalog_name = "metastore_Assignment"
  depends_on           = [databricks_metastore.this]
}

resource "databricks_storage_credential" "external" {
  name = "storage_cred_unity"
  azure_managed_identity {
    access_connector_id = azurerm_databricks_access_connector.example.id
  }
  
  comment = "External Storage Account"
}


resource "databricks_external_location" "external" {
  name = "external"
  url = format("abfss://%s@%s.dfs.core.windows.net/",
    azurerm_storage_container.unity_catalog.name,

  azurerm_storage_account.unity_catalog.name)
  credential_name = databricks_storage_credential.external.id
  comment         = "Managed by TF"
  
}




# # this part is only for unity catalog


resource "azurerm_databricks_access_connector" "external" {
  name                = "databricks-ext-acc"
  location            = azurerm_databricks_workspace.example.location
  resource_group_name = azurerm_resource_group.example.name

  identity {
    type = "SystemAssigned"
  }
}

 resource "azurerm_role_assignment" "ex_table" {
  scope                = azurerm_storage_account.ex_table.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_access_connector.external.identity[0].principal_id
  depends_on           = [azurerm_databricks_access_connector.external]
}

resource "azurerm_storage_account" "ex_table" {
  name                = "externaltablestorage"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  # tags                     = data.azurerm_resource_group.this.tags
  account_tier             = "Standard"
  account_replication_type = "GRS"
  is_hns_enabled           = true
}


resource "azurerm_storage_container" "ex_table" {
  name                  = "data-container"
  storage_account_name  = azurerm_storage_account.ex_table.name
  container_access_type = "private"
}

# # done at here 
resource "databricks_storage_credential" "storage_external" {
  name = "external_storage_cred"
  azure_managed_identity {
    access_connector_id = azurerm_databricks_access_connector.external.id
  }
  depends_on = [  azurerm_role_assignment.ex_table]
 
  comment = "External Storage Account"
}
resource "databricks_external_location" "storage_external" {
  name = "extb"
  url = format("abfss://%s@%s.dfs.core.windows.net/",azurerm_storage_container.ex_table.name,azurerm_storage_account.ex_table.name)
  credential_name = databricks_storage_credential.storage_external.id
  comment         = "Managed by TF"
  
}



# # will done

resource "databricks_catalog" "ext" {
  name         = "dest_catalog"
  comment      = "this catalog is managed by terraform"
  properties = {
    purpose = "testing"
  }
}
resource "databricks_schema" "ext" {
  catalog_name = databricks_catalog.ext.id
  name         = "dest_schema"
  comment      = "this database is managed by terraform"
  properties = {
    kind = "various"
  }
}


resource "databricks_notebook" "this" {
  path     = "/Terraform/notebook1"
  language = "SQL"
  content_base64 = base64encode(<<-EOT
    


    sync schema dest_catalog.dest_schema from hive_metastore.source_database;
    

   EOT
  )
}

      


# output "job_url" {
#   value = databricks_job.this.url
# }
resource "databricks_cluster" "this" {
  cluster_name            = "Cluster_demo"
  node_type_id            = "Standard_DS3_v2"
  spark_version           = "13.3.x-scala2.12"
  autotermination_minutes = 10
  num_workers             = 0
  data_security_mode      = "SINGLE_USER"

  spark_conf = {
    "spark.databricks.cluster.profile" : "singleNode",
    "spark.master" : "local[*]",
    "spark.hadoop.javax.jdo.option.ConnectionDriverName" : "com.microsoft.sqlserver.jdbc.SQLServerDriver",
    "spark.hadoop.javax.jdo.option.ConnectionURL" : "jdbc:sqlserver://sqldemotesting.database.windows.net:1433;database=sqldemo1;encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30;",
    "spark.hadoop.metastore.catalog.default" : "hive",
    "spark.databricks.delta.preview.enabled" : true,
    "spark.hadoop.javax.jdo.option.ConnectionUserName" : "sqladmin",
    "datanucleus.fixedDatastore" : true,
    "spark.hadoop.javax.jdo.option.ConnectionPassword" : "admin@123",
    "datanucleus.autoCreateSchema" : false,
    "spark.sql.hive.metastore.jars" : "builtin",
    "spark.sql.hive.metastore.version" : "2.3.9",
    "fs.azure.account.key.externaltablestorage.dfs.core.windows.net":"XVCN3WsLpeQnOfCyENSDs+WZdKGZUbxPlJcmQjEdRg25oNBxZHHQvsnk4EL4qzPGU83XQvTdb23f+AStHsdnpA==",
    "fs.azure.account.key.azurestorageunity.dfs.core.windows.net":"ikprgm6itTtraWRP85kukMh9kXZcoB2w9GTfENHsyGd43KZS1C+sGLKq//bCBpZUAOSSlequ8l8k+AStglTcpA==",
    # "fs.azure.account.key.hivedbstoragetable.dfs.core.windows.net":"FH943o1iAAdKocWGI1/lFbdTGf6jzYV/4b6YBWqGhJZHlM6NEosF8zSWgzjFiHUgPRRIxH+p5eVl+AStAAOpNg==",

  }

  custom_tags = {
    "ResourceClass" = "SingleNode"
  }
  
}
  



# output "cluster_url" {
#   value = databricks_cluster.this.url
# }

 resource "databricks_job" "this" {
  name = "job1"
  existing_cluster_id = databricks_cluster.this.cluster_id
    notebook_task {
      notebook_path = databricks_notebook.this.path
      }
    #  timeout_seconds = 3600
    
   }