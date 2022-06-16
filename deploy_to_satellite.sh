#!/bin/bash

function getAPPUrlSatConfig() {
  for filename in $(find /artifacts/${MANIFEST_DIR} -type f -print); do   
    echo "file name is ${filename}"
    route_name=$(yq -o=json eval ${filename} |   jq -r  'select(.kind=="Route") | .metadata.name')  
     if [ ! -z "${route_name}" ]; then
      if grep -q "razee/watch-resource: lite" ${filename}; then
        break;
      else 
       echo "Did not find [razee/watch-resource: lite] label in your deployment file.  Unable to fetch the application url. Please visit https://cloud.ibm.com/docs/satellite?topic=satellite-satcon-manage&mhsrc=ibmsearch_a&mhq=razee%2Fwatch-resource%3A+lite#satconfig-enable-watchkeeper-specific"
       return
      fi
    fi
  done

  if [ -z "${route_name}" ]; then
    echo "Did not find deployment of type route. Unable to fetch the application url....."
    return
  fi

  for ITER in {1..30}
    do
        resources_ids=$(ic sat resource ls -output json |  jq -r ".resources.resources[] | select(.searchableData.name==\"$route_name\") | select(.searchableData.namespace==\"$CLUSTER_NAMESPACE\") | .id ")
        resource_id=$(echo "${resources_ids}" | awk '{print $1}')
        if [ -z "${resource_id}" ]
        then
          echo "Waiting for application deployment to be on completed....${ITER}"
        else
          APPURL=$(ibmcloud sat resource get --resource  "${resource_id}" --output json | jq -r '.resource.data' | jq -r '.status.ingress[0].host')
        fi
      if [ -z  "${APPURL}"  ] || [[  "${APPURL}" = "null"  ]]; then 
        echo "Waiting for APPURL ...."
        sleep 20
      else
        break
      fi
    done
}

function createAndDeploySatelliteConfig() {

echo "=========================================================="
APP_NAME=$1
SAT_CONFIG=$2
SAT_CONFIG_VERSION=$3
DEPLOY_FILE=$4
echo "Creating config for ${SAT_CONFIG}...."

export SATELLITE_SUBSCRIPTION="${APP_NAME}-${SAT_CONFIG}"
export SAT_CONFIG_VERSION
if ! ic sat config version get --config "${APP_NAME}" --version "${SAT_CONFIG_VERSION}" &>/dev/null; then
  echo -e "Current resource ${SAT_CONFIG_VERSION} not found, creating it"
  if ! ibmcloud sat config get --config "${APP_NAME}" &>/dev/null ; then
    ibmcloud sat config create --name "${APP_NAME}"
  fi
  echo "deployment file is ${DEPLOY_FILE}"
  ibmcloud sat config version create --name "${SAT_CONFIG_VERSION}" --config "${APP_NAME}" --file-format yaml --read-config "${DEPLOY_FILE}"
else
  echo -e "Current resource ${SAT_CONFIG_VERSION} already found."
fi

EXISTING_SUB=$(ibmcloud sat subscription ls -q | grep "${SATELLITE_SUBSCRIPTION}" || true)
  if [ -z "${EXISTING_SUB}" ]; then
    ibmcloud sat subscription create --name "${SATELLITE_SUBSCRIPTION}" --group "${SATELLITE_CLUSTER_GROUP}" --version "${SAT_CONFIG_VERSION}" --config "${APP_NAME}"
  else
    ibmcloud sat subscription update --subscription "${SATELLITE_SUBSCRIPTION}" -f --group "${SATELLITE_CLUSTER_GROUP}" --version "${SAT_CONFIG_VERSION}"
fi
}

ls -laht /artifacts/${MANIFEST_DIR}
commit=$(git log -1 --pretty=format:%h)
for filename in $(find /artifacts/${MANIFEST_DIR} -type f -print); do   
  echo "file name is ${filename}" 
  config_name=$(basename ${filename} | cut -d. -f1)
  config_name_version=${config_name}_${commit} 
  #echo "updating the namespaces in the deployment file."
  #yq e ".metadata.namespace = \"${CLUSTER_NAMESPACE}\"" ${filename} >> test_${filename}
  createAndDeploySatelliteConfig ${APP_NAME} ${config_name} ${config_name_version} ${filename}
done

getAPPUrlSatConfig
echo "APPURL ${APPURL}"


