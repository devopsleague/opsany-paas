#!/bin/bash
#******************************************
# Author:       Jason Zhao
# Email:        zhaoshundong@opsany.com
# Organization: OpsAny https://www.opsany.com/
# Description:  OpsAny SAAS Install Script
#******************************************

# Data/Time
CTIME=$(date "+%Y-%m-%d-%H-%M")

# Shell Envionment Variables
CDIR=$(pwd)
SHELL_NAME="saas-install.sh"
SHELL_LOG="${SHELL_NAME}.log"

# Check SAAS Package
if [ ! -d ../../opsany-saas ];then
    echo "======Download the SAAS package first======"
    exit;
fi

# Configuration file write to DB
pip3 install requests==2.25.1 grafana-api==1.0.3 mysql-connector==2.2.9 SQLAlchemy==1.4.22 -i http://mirrors.aliyun.com/pypi/simple/ --trusted-host mirrors.aliyun.com
cd $CDIR 
grep '^[A-Z]' install.config > install.env
source ./install.env && rm -f install.env
cd ../saas/
python3 add_env.py

# Install Inspection
cd ${CDIR}
if [ ! -f ./install.config ];then
      echo "Please Change Directory to /opt/opsany-paas/install"
      exit
else
    grep '^[A-Z]' install.config > install.env
    source ./install.env && rm -f install.env
fi

# Shell Log Record
shell_log(){
    LOG_INFO=$1
    echo "----------------$CTIME ${SHELL_NAME} : ${LOG_INFO}----------------"
    echo "$CTIME ${SHELL_NAME} : ${LOG_INFO}" >> ${SHELL_LOG}
}

# Check Install requirement
saas_init(){
    mkdir -p ${INSTALL_PATH}/{zabbix-volume/alertscripts,zabbix-volume/externalscripts,zabbix-volume/snmptraps,grafana-volume/plugins}
    mkdir -p ${INSTALL_PATH}/uploads/monitor/heartbeat-monitors.d
}

# Start SaltStack 
saltstack_install(){
    shell_log "======Start SaltStack======"
    docker run --restart=always --name opsany-saltstack --detach \
        --publish 4505:4505 --publish 4506:4506 --publish 8005:8005 \
        -v ${INSTALL_PATH}/logs:${INSTALL_PATH}/logs \
        -v ${INSTALL_PATH}/salt-volume/srv/:/srv/ \
        -v ${INSTALL_PATH}/salt-volume/certs/:/etc/pki/tls/certs/ \
        -v ${INSTALL_PATH}/salt-volume/etc/salt/:/etc/salt/ \
        -v ${INSTALL_PATH}/salt-volume/etc/salt/master.d:/etc/salt/master.d \
        -v ${INSTALL_PATH}/salt-volume/cache/:/var/cache/salt/ \
        -v /etc/localtime:/etc/localtime:ro \
        ${PAAS_DOCKER_REG}/opsany-saltstack:${PAAS_VERSION}
    sleep 20
    
    docker exec opsany-saltstack salt-key -A -y
}

# Start Zabbix
zabbix_install(){
    shell_log "=====Start Zabbix======"
    docker run --restart=always --name opsany-zabbix-server -t \
      -e DB_SERVER_HOST="${MYSQL_SERVER_IP}" \
      -e MYSQL_DATABASE="${ZABBIX_DB_NAME}" \
      -e MYSQL_USER="${ZABBIX_DB_USER}" \
      -e MYSQL_PASSWORD="${ZABBIX_DB_PASSWORD}" \
      -e MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}" \
      -e ZBX_JAVAGATEWAY="zabbix-java-gateway" \
      -p 10051:10051 \
      -v ${INSTALL_PATH}/zabbix-volume/alertscripts:/usr/lib/zabbix/alertscripts \
      -v ${INSTALL_PATH}/zabbix-volume/externalscripts:/usr/lib/zabbix/externalscripts \
      -v ${INSTALL_PATH}/zabbix-volume/snmptraps:/var/lib/zabbix/snmptraps \
      -v /etc/localtime:/etc/localtime:ro \
      -d ${PAAS_DOCKER_REG}/zabbix-server-mysql:alpine-5.0-latest

    sleep 20
    
    docker run --restart=always --name opsany-zabbix-web -t \
      -e ZBX_SERVER_HOST="${MYSQL_SERVER_IP}" \
      -e DB_SERVER_HOST="${MYSQL_SERVER_IP}" \
      -e MYSQL_DATABASE="${ZABBIX_DB_NAME}" \
      -e MYSQL_USER="${ZABBIX_DB_USER}" \
      -e MYSQL_PASSWORD="${ZABBIX_DB_PASSWORD}" \
      -e MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}" \
      -v /etc/localtime:/etc/localtime:ro \
      -p 8006:8080 \
      -d ${PAAS_DOCKER_REG}/zabbix-web-nginx-mysql:alpine-5.0-latest
}

# Start Grafana
grafana_install(){
    # Grafana
    shell_log "=====Start Grafana======"
    docker run -d --restart=always --name opsany-grafana \
    -v ${INSTALL_PATH}/conf/grafana/grafana.ini:/etc/grafana/grafana.ini \
    -v ${INSTALL_PATH}/conf/grafana/grafana.key:/etc/grafana/grafana.key \
    -v ${INSTALL_PATH}/conf/grafana/grafana.pem:/etc/grafana/grafana.pem \
    -v /etc/localtime:/etc/localtime:ro \
    -p 8007:3000 \
    ${PAAS_DOCKER_REG}/opsany-grafana:7.3.5
}

# Start Elasticsearch
es_install(){
    #Elasticsearch
    shell_log "====Start Elasticsearch"
    docker run -d --restart=always --name opsany-elasticsearch \
    -e "discovery.type=single-node" \
    -e "ELASTIC_PASSWORD=${ES_PASSWORD}" \
    -e "xpack.license.self_generated.type=trial" \
    -e "xpack.security.enabled=true" \
    -e "bootstrap.memory_lock=true" \
    -e "ES_JAVA_OPTS=-Xms512m -Xmx512m" \
    -v /etc/localtime:/etc/localtime:ro \
    -p 9200:9200 -p 9300:9300 \
    ${PAAS_DOCKER_REG}/elasticsearch:7.12.0
    
    #heartbeat
    shell_log "====Start Heartbeat===="
    docker run -d --restart=always --name opsany-heartbeat \
    -v ${INSTALL_PATH}/conf/heartbeat.yml:/etc/heartbeat/heartbeat.yml \
    -v ${INSTALL_PATH}/uploads/monitor/heartbeat-monitors.d:/etc/heartbeat/monitors.d \
    -v ${INSTALL_PATH}/logs:/var/log/heartbeat \
    -v /etc/localtime:/etc/localtime:ro \
    ${PAAS_DOCKER_REG}/opsany-heartbeat:7.13.2
    
}

# SaaS DB Initialize
saas_db_init(){
    shell_log "======MySQL Initialize======"
    #esb
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" opsany_paas < ./init/esb-init/esb_api_doc.sql
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" opsany_paas < ./init/esb-init/esb_channel.sql
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" opsany_paas < ./init/esb-init/esb_component_system.sql
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" opsany_paas -e "INSERT INTO esb_user_auth_token VALUES (1, 'workbench', 'admin', 'opsany-esb-auth-token-9e8083137204', '2031-01-01 10:27:18', '2020-12-08 10:20:22', '2020-12-08 10:20:24'), (2, 'rbac', 'admin', 'opsany-esb-auth-token-9e8083137204', '2031-01-01 10:27:18', '2020-12-08 10:20:22', '2020-12-08 10:20:24'), (3, 'cmdb', 'admin', 'opsany-esb-auth-token-9e8083137204', '2031-01-01 10:27:18', '2020-12-08 10:20:22', '2020-12-08 10:20:24'), (4, 'job', 'admin', 'opsany-esb-auth-token-9e8083137204', '2031-01-01 10:27:18', '2020-12-08 10:20:22', '2020-12-08 10:20:24'), (5, 'control', 'admin', 'opsany-esb-auth-token-9e8083137204', '2031-01-01 10:27:18', '2020-12-08 10:20:22', '2020-12-08 10:20:24'), (6, 'monitor', 'admin', 'opsany-esb-auth-token-9e8083137204', '2031-01-01 10:27:18', '2020-12-08 10:20:22', '2020-12-08 10:20:24'), (7, 'cmp', 'admin', 'opsany-esb-auth-token-9e8083137204', '2031-01-01 10:27:18', '2020-12-08 10:20:22', '2020-12-08 10:20:24');"
    
    #rbac
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "create database rbac DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;"
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "grant all on rbac.* to rbac@'%' identified by "\"${MYSQL_OPSANY_RBAC_PASSWORD}\"";"
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "grant all on rbac.* to opsany@'%' identified by "\"${MYSQL_OPSANY_PASSWORD}\"";"
    
    #workbench
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "create database workbench DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;"
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "grant all on workbench.* to workbench@'%' identified by "\"${MYSQL_OPSANY_WORKBENCH_PASSWORD}\"";"
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "grant all on workbench.* to opsany@'%' identified by "\"${MYSQL_OPSANY_PASSWORD}\"";"
    
    #cmdb
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "create database cmdb DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;"
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "grant all on cmdb.* to cmdb@'%' identified by "\"${MYSQL_OPSANY_CMDB_PASSWORD}\"";"
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "grant all on cmdb.* to opsany@'%' identified by "\"${MYSQL_OPSANY_PASSWORD}\"";"
    
    #control
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "create database control DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;"
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "grant all on control.* to control@'%' identified by "\"${MYSQL_OPSANY_CONTROL_PASSWORD}\"";"
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "grant all on control.* to opsany@'%' identified by "\"${MYSQL_OPSANY_PASSWORD}\"";"
    
    #job
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "create database job DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;"
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "grant all on job.* to job@'%' identified by "\"${MYSQL_OPSANY_JOB_PASSWORD}\"";"
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "grant all on job.* to opsany@'%' identified by "\"${MYSQL_OPSANY_PASSWORD}\"";"
    
    #monitor
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "create database monitor DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;"
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "grant all on monitor.* to monitor@'%' identified by "\"${MYSQL_OPSANY_MONITOR_PASSWORD}\"";"
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "grant all on monitor.* to opsany@'%' identified by "\"${MYSQL_OPSANY_PASSWORD}\"";" 
    
    #cmp
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "create database cmp DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;"
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "grant all on cmp.* to cmp@'%' identified by "\"${MYSQL_OPSANY_CMP_PASSWORD}\"";"
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "grant all on cmp.* to opsany@'%' identified by "\"${MYSQL_OPSANY_PASSWORD}\"";" 
    
    #devops
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "create database devops DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;"
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "grant all on devops.* to devops@'%' identified by "\"${MYSQL_OPSANY_DEVOPS_PASSWORD}\"";"
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "grant all on devops.* to opsany@'%' identified by "\"${MYSQL_OPSANY_PASSWORD}\"";" 

    #bastion
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "create database bastion DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;"
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "grant all on bastion.* to bastion@'%' identified by "\"${MYSQL_OPSANY_BASTION_PASSWORD}\"";"
    mysql -h "${MYSQL_SERVER_IP}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "grant all on bastion.* to opsany@'%' identified by "\"${MYSQL_OPSANY_PASSWORD}\"";" 
}

# MonogDB Initialize
mongodb_init(){
    shell_log "======MongoDB Initialize======"
    mongo --host $MONGO_SERVER_IP -u $MONGO_INITDB_ROOT_USERNAME -p$MONGO_INITDB_ROOT_PASSWORD <<END
    use cmdb;
    db.createUser({user: "cmdb",pwd: "$MONGO_CMDB_PASSWORD",roles: [ { role: "readWrite", db: "cmdb" } ]});
    use job;
    db.createUser( {user: "job",pwd: "$MONGO_JOB_PASSWORD",roles: [ { role: "readWrite", db: "job" } ]});
    use cmp;
    db.createUser( {user: "cmp",pwd: "$MONGO_CMP_PASSWORD",roles: [ { role: "readWrite", db: "cmp" } ]});
    use workbench;
    db.createUser( {user: "workbench",pwd: "$MONGO_WORKBENCH_PASSWORD",roles: [ { role: "readWrite", db: "workbench" } ]});
    use devops;
    db.createUser( {user: "devops",pwd: "$MONGO_DEVOPS_PASSWORD",roles: [ { role: "readWrite", db: "devops" } ]});
    use monitor;
    db.createUser( {user: "monitor",pwd: "$MONGO_MONITOR_PASSWORD",roles: [ { role: "readWrite", db: "monitor" } ]});
    exit;
END
    shell_log "======MongoDB Initialize End======"
    
    shell_log "======CMDB Initialize======"
    mongoimport --host $MONGO_SERVER_IP -u cmdb -p${MONGO_CMDB_PASSWORD} --db cmdb --drop --collection field_group < ./init/cmdb-init/field_group.json
    mongoimport --host $MONGO_SERVER_IP -u cmdb -p${MONGO_CMDB_PASSWORD} --db cmdb --drop --collection icon_model < ./init/cmdb-init/icon_model.json
    mongoimport --host $MONGO_SERVER_IP -u cmdb -p${MONGO_CMDB_PASSWORD} --db cmdb --drop --collection link_relationship_model < ./init/cmdb-init/link_relationship_model.json
    mongoimport --host $MONGO_SERVER_IP -u cmdb -p${MONGO_CMDB_PASSWORD} --db cmdb --drop --collection model_field < ./init/cmdb-init/model_field.json
    mongoimport --host $MONGO_SERVER_IP -u cmdb -p${MONGO_CMDB_PASSWORD} --db cmdb --drop --collection model_group < ./init/cmdb-init/model_group.json
    mongoimport --host $MONGO_SERVER_IP -u cmdb -p${MONGO_CMDB_PASSWORD} --db cmdb --drop --collection model_info < ./init/cmdb-init/model_info.json
    shell_log "======Initialize End======"
}

# SaaS Reconfigure
saas_reconfigure(){
    shell_log "======SaaS Deploy======"
    cd $CDIR
    cd ../../opsany-saas/
    /bin/cp *.tar.gz ../opsany-paas/saas/
}

# SaaS Deploy
saas_deploy(){
    cd $CDIR
    cd ../saas/ && ls *.tar.gz
    if [ $? -ne 0 ];then
        echo "Please Download SAAS first" && exit
    fi
    python3 deploy.py --domain $DOMAIN_NAME --username admin --password admin --file_name rbac-opsany-*.tar.gz
    python3 deploy.py --domain $DOMAIN_NAME --username admin --password admin --file_name workbench-opsany-*.tar.gz
    python3 deploy.py --domain $DOMAIN_NAME --username admin --password admin --file_name cmdb-opsany-*.tar.gz
    python3 deploy.py --domain $DOMAIN_NAME --username admin --password admin --file_name control-opsany-*.tar.gz
    python3 deploy.py --domain $DOMAIN_NAME --username admin --password admin --file_name job-opsany-*.tar.gz
    python3 deploy.py --domain $DOMAIN_NAME --username admin --password admin --file_name monitor-opsany-*.tar.gz
    python3 deploy.py --domain $DOMAIN_NAME --username admin --password admin --file_name cmp-opsany-*.tar.gz
    python3 deploy.py --domain $DOMAIN_NAME --username admin --password admin --file_name devops-opsany-*.tar.gz
    python3 deploy.py --domain $DOMAIN_NAME --username admin --password admin --file_name bastion-opsany-*.tar.gz
    python3 init_script.py --domain $DOMAIN_NAME --private_ip $LOCAL_IP
    chmod +x /etc/rc.d/rc.local
    echo "sleep 60 && /bin/bash /opt/opsany/saas-restart.sh" >> /etc/rc.d/rc.local
}

# Main
main(){
    saas_init
    saas_db_init
    mongodb_init
    saltstack_install
    zabbix_install
    grafana_install
    es_install
    saas_reconfigure
    saas_deploy
}

main