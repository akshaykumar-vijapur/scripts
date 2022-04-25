#!/bin/bash

function getAPPUrlSatConfig() {

  route_name=$(yq -o=json eval ${DEPLOYMENT_FILE} |   jq -r  'select(.kind=="Route") | .metadata.name')
  if [ -z "${route_name}" ]; then
    echo "Did not find deployment of type route. Unable to fetch the application url....."
    return
  fi

  for ITER in {1..30}
    do
        resources_ids=$(ic sat resource ls -output json |  jq -r ".resources.resources[] | select(.searchableData.name==\"$route_name\") | .id ")
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
SAT_CONFIG=$1
SAT_CONFIG_VERSION=$2
KUBE_RESOURCE=$3
DEPLOY_FILE=$4
echo "Creating config for $SAT_CONFIG...."

export SATELLITE_SUBSCRIPTION="$SAT_CONFIG-$SATELLITE_CLUSTER_GROUP"
export SAT_CONFIG_VERSION
if ! ic sat config version get --config "$SAT_CONFIG" --version "$SAT_CONFIG_VERSION" &>/dev/null; then
  echo -e "Current resource ${KUBE_RESOURCE} not found in ${IBMCLOUD_IKS_CLUSTER_NAMESPACE}, creating it"
  if ! ibmcloud sat config get --config "$SAT_CONFIG" &>/dev/null ; then
    ibmcloud sat config create --name "$SAT_CONFIG"
  fi
  echo "deployment file is ${DEPLOY_FILE}"
  ibmcloud sat config version create --name "$SAT_CONFIG_VERSION" --config "$SAT_CONFIG" --file-format yaml --read-config "${DEPLOY_FILE}"
else
  echo -e "Current resource ${KUBE_RESOURCE} already found in ${IBMCLOUD_IKS_CLUSTER_NAMESPACE}"
fi

EXISTING_SUB=$(ibmcloud sat subscription ls -q | grep "$SATELLITE_SUBSCRIPTION" || true)
  if [ -z "${EXISTING_SUB}" ]; then
    ibmcloud sat subscription create --name "$SATELLITE_SUBSCRIPTION" --group "$SATELLITE_CLUSTER_GROUP" --version "$SAT_CONFIG_VERSION" --config "$SAT_CONFIG"
  else
    ibmcloud sat subscription update --subscription "$SATELLITE_SUBSCRIPTION" -f --group "$SATELLITE_CLUSTER_GROUP" --version "$SAT_CONFIG_VERSION"
fi
}


for filename in $(find /artifacts/${MANIFEST_DIR} -type f -print); do   
  echo "file name is ${filename}"  
  echo " " >> ${DEPLOYMENT_FILE}
  echo "---" >> ${DEPLOYMENT_FILE}
  yq e ".metadata.namespace = \"${CLUSTER_NAMESPACE}\"" ${filename} >> ${DEPLOYMENT_FILE}
done


yq e  -i '.metadata.labels.razee/watch-resource = "lite"' ${DEPLOYMENT_FILE}
commit=$(git log --format="%H" -n 1)
createAndDeploySatelliteConfig ${APP_NAME} ${commit} deployment_file ${DEPLOYMENT_FILE} 
getAPPUrlSatConfig
echo "APPURL ${APPURL}"


