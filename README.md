# wh-logistics

https://towardsdatascience.com/shared-external-hive-metastore-with-azure-databricks-and-synapse-spark-pools-8d611c677688#:~:text=To%20help%20structure%20your%20data,delta%2C%20CSV%2C%20etc).

Steps to do in synapse workspace 

 

%%configure -f
{
    "conf":{
        "spark.sql.hive.metastore.version":"2.3",
        "spark.hadoop.hive.synapse.externalmetastore.linkedservice.name":"AzureSqlDatabase",
        "spark.sql.hive.metastore.jars":"/opt/hive-metastore/lib-2.3/*:/usr/hdp/current/hadoop-client/lib/*:/usr/hdp/current/hadoop-client/*",
       
    }
}


CREATE EXTERNAL TABLE source_database.example_table(id int,name string)
USING DELTA
OPTIONS (
  'compression' = 'snappy'
)
LOCATION 'abfss://data-container@externaltablestorage.dfs.core.windows.net/folder'
