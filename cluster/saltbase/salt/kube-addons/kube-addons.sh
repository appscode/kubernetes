#!/bin/bash

# Copyright 2014 The Kubernetes Authors All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# The business logic for whether a given object should be created
# was already enforced by salt, and /etc/kubernetes/addons is the
# managed result is of that. Start everything below that directory.
KUBECTL=${KUBECTL_BIN:-/usr/local/bin/kubectl}

ADDON_CHECK_INTERVAL_SEC=${TEST_ADDON_CHECK_INTERVAL_SEC:-600}

SYSTEM_NAMESPACE=kube-system
token_dir=${TOKEN_DIR:-/srv/kubernetes}
trusty_master=${TRUSTY_MASTER:-false}
addons_dir=${ADDONS_DIR:-/etc/kubernetes/addons}

function ensure_python() {
  if ! python --version > /dev/null 2>&1; then
    echo "No python on the machine, will use a python image"
    local -r PYTHON_IMAGE=python:2.7-slim-pyyaml
    export PYTHON="docker run --interactive --rm --net=none ${PYTHON_IMAGE} python"
  else
    export PYTHON=python
  fi
}

function create-cluster-metadata() {
  read -r -d '' cfgmapyaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-metadata
  namespace: default
data:
  appscode-ns: ${APPSCODE_NS}
  cluster-name: ${INSTANCE_PREFIX}
  appscode-api-grpc-endpoint: ${APPSCODE_API_GRPC_ENDPOINT}
  appscode-api-http-endpoint: ${APPSCODE_API_HTTP_ENDPOINT}
EOF
  create-resource-from-string "${cfgmapyaml}" 100 10 "ConfigMap-for-cluster-metadata" "default" &

  read -r -d '' cfgmapyaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-metadata
  namespace: ${SYSTEM_NAMESPACE}
data:
  appscode-ns: ${APPSCODE_NS}
  cluster-name: ${INSTANCE_PREFIX}
  appscode-api-grpc-endpoint: ${APPSCODE_API_GRPC_ENDPOINT}
  appscode-api-http-endpoint: ${APPSCODE_API_HTTP_ENDPOINT}
EOF
  create-resource-from-string "${cfgmapyaml}" 100 10 "ConfigMap-for-cluster-metadata" "${SYSTEM_NAMESPACE}" &
}

function create-ossec-secret() {
  local -r name=$1
  local -r safe_name=$(tr -s ':_' '--' <<< "${name}")
  local -r ossec_api_user='agent'

    read -r -d '' auth <<EOF
${ossec_api_user},${APPSCODE_OSSEC_API_PASSWORD}
EOF
  local -r auth_base64=$(echo "${auth}" | base64 -w0)

  local htauth=$(htpasswd -nb ${ossec_api_user} ${APPSCODE_OSSEC_API_PASSWORD})
  local -r htauth_base64=$(echo "${htauth}" | base64 -w0)

  read -r -d '' secretyaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: appscode-${safe_name}
  namespace: ${SYSTEM_NAMESPACE}
type: Opaque
data:
  basic-auth.csv: ${auth_base64}
  htpasswd: ${htauth_base64}
  server.crt: ${OSSEC_SERVER_CERT}
  server.key: ${OSSEC_SERVER_KEY}
EOF
  create-resource-from-string "${secretyaml}" 100 10 "Secret-for-${safe_name}" "${SYSTEM_NAMESPACE}" &
}

function create-appscode-secret() {
  local -r secret=$1
  local -r name=$2
  local -r filename=$3
  local -r namespace=$4
  local -r safe_name=$(tr -s ':_' '--' <<< "${name}")

  local -r secret_base64=$(echo "${secret}" | base64 -w0)
  read -r -d '' secretyaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: appscode-${safe_name}
  namespace: ${namespace}
type: Opaque
data:
  ${filename}: ${secret_base64}
EOF
  create-resource-from-string "${secretyaml}" 100 10 "Secret-for-${safe_name}" "${namespace}" &
}

function create-icinga-secret() {
  read -r -d '' env_file <<EOF
ICINGA_WEB_HOST=127.0.0.1
ICINGA_WEB_PORT=5432
ICINGA_WEB_DB=icingawebdb
ICINGA_WEB_USER=${APPSCODE_ICINGA_WEB_USER}
ICINGA_WEB_PASSWORD=${APPSCODE_ICINGA_WEB_PASSWORD}
ICINGA_IDO_HOST=127.0.0.1
ICINGA_IDO_PORT=5432
ICINGA_IDO_DB=icingaidodb
ICINGA_IDO_USER=${APPSCODE_ICINGA_IDO_USER}
ICINGA_IDO_PASSWORD=${APPSCODE_ICINGA_IDO_PASSWORD}
ICINGA_API_USER=${APPSCODE_ICINGA_API_USER}
ICINGA_API_PASSWORD=${APPSCODE_ICINGA_API_PASSWORD}
EOF
  mkdir -p /srv/icinga2/secrets
  echo "${env_file}" > /srv/icinga2/secrets/.env

  local -r name='icinga'
  local -r safe_name=$(tr -s ':_' '--' <<< "${name}")

  local -r env_file_base64=$(echo "${env_file}" | base64 -w0)
  read -r -d '' secretyaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: appscode-${safe_name}
  namespace: ${SYSTEM_NAMESPACE}
type: Opaque
data:
  .env: ${env_file_base64}
  ca.crt: ${CA_CERT}
  icinga.crt: ${DEFAULT_LB_CERT}
  icinga.key: ${DEFAULT_LB_KEY}
EOF
  create-resource-from-string "${secretyaml}" 100 10 "Secret-for-${safe_name}" "${SYSTEM_NAMESPACE}" &
}

function create-appscode-secrets() {
  create-cluster-metadata

  read -r -d '' apitoken <<EOF
{
  "namespace":"${APPSCODE_NS}",
  "token":"${APPSCODE_API_TOKEN}"
}
EOF
  mkdir -p /var/run/secrets/appscode
  echo "${apitoken}" > /var/run/secrets/appscode/api-token
  create-appscode-secret "${apitoken}" "api-token" "api-token" "${SYSTEM_NAMESPACE}"

  create-icinga-secret

    read -r -d '' influx <<EOF
INFLUX_HOST=monitoring-influxdb.kube-system
INFLUX_API_PORT=8086
INFLUX_DB=k8s
INFLUX_ADMIN_USER=${APPSCODE_INFLUX_ADMIN_USER}
INFLUX_ADMIN_PASSWORD=${APPSCODE_INFLUX_ADMIN_PASSWORD}
INFLUX_READ_USER=${APPSCODE_INFLUX_READ_USER}
INFLUX_READ_PASSWORD=${APPSCODE_INFLUX_READ_PASSWORD}
INFLUX_WRITE_USER=${APPSCODE_INFLUX_WRITE_USER}
INFLUX_WRITE_PASSWORD=${APPSCODE_INFLUX_WRITE_PASSWORD}
EOF
  create-appscode-secret "${influx}" "influx" ".admin" "${SYSTEM_NAMESPACE}"

  if [[ "$ENABLE_CLUSTER_SECURITY" == "appscode" ]]; then
    create-ossec-secret "ossec"

    local -r agentyaml=`cat ${addons_dir}/appscode-ossec-wazuh/ossec-agent-daemonset.yaml`
    create-resource-from-string "${agentyaml}" 100 10 "daemonset-for-ossec-agent" "${SYSTEM_NAMESPACE}" &
  fi
}

function create-kubeconfig-secret() {
  local -r token=$1
  local -r username=$2
  local -r server=$3
  local -r safe_username=$(tr -s ':_' '--' <<< "${username}")

  # Make a kubeconfig file with the token.
  if [[ ! -z "${CA_CERT:-}" ]]; then
    # If the CA cert is available, put it into the secret rather than using
    # insecure-skip-tls-verify.
    read -r -d '' kubeconfig <<EOF
apiVersion: v1
kind: Config
users:
- name: ${username}
  user:
    token: ${token}
clusters:
- name: local
  cluster:
     server: ${server}
     certificate-authority-data: ${CA_CERT}
contexts:
- context:
    cluster: local
    user: ${username}
    namespace: ${SYSTEM_NAMESPACE}
  name: service-account-context
current-context: service-account-context
EOF
  else
    read -r -d '' kubeconfig <<EOF
apiVersion: v1
kind: Config
users:
- name: ${username}
  user:
    token: ${token}
clusters:
- name: local
  cluster:
     server: ${server}
     insecure-skip-tls-verify: true
contexts:
- context:
    cluster: local
    user: ${username}
    namespace: ${SYSTEM_NAMESPACE}
  name: service-account-context
current-context: service-account-context
EOF
  fi

  local -r kubeconfig_base64=$(echo "${kubeconfig}" | base64 -w0)
  read -r -d '' secretyaml <<EOF
apiVersion: v1
data:
  kubeconfig: ${kubeconfig_base64}
kind: Secret
metadata:
  name: token-${safe_username}
type: Opaque
EOF
  create-resource-from-string "${secretyaml}" 100 10 "Secret-for-token-for-user-${username}" "${SYSTEM_NAMESPACE}" &
}

# $1 filename of addon to start.
# $2 count of tries to start the addon.
# $3 delay in seconds between two consecutive tries
# $4 namespace
function start_addon() {
  local -r addon_filename=$1;
  local -r tries=$2;
  local -r delay=$3;
  local -r namespace=$4

  create-resource-from-string "$(cat ${addon_filename})" "${tries}" "${delay}" "${addon_filename}" "${namespace}"
}

# $1 string with json or yaml.
# $2 count of tries to start the addon.
# $3 delay in seconds between two consecutive tries
# $4 name of this object to use when logging about it.
# $5 namespace for this object
function create-resource-from-string() {
  local -r config_string=$1;
  local tries=$2;
  local -r delay=$3;
  local -r config_name=$4;
  local -r namespace=$5;
  while [ ${tries} -gt 0 ]; do
    echo "${config_string}" | ${KUBECTL} --namespace="${namespace}" create -f - && \
        echo "== Successfully started ${config_name} in namespace ${namespace} at $(date -Is)" && \
        return 0;
    let tries=tries-1;
    echo "== Failed to start ${config_name} in namespace ${namespace} at $(date -Is). ${tries} tries remaining. =="
    sleep ${delay};
  done
  return 1;
}

# $1 is the directory containing all of the docker images
function load-docker-images() {
  local success
  local restart_docker
  while true; do
    success=true
    restart_docker=false
    for image in "$1/"*; do
      timeout 30 docker load -i "${image}" &>/dev/null
      rc=$?
      if [[ "$rc" == 124 ]]; then
        restart_docker=true
      elif [[ "$rc" != 0 ]]; then
        success=false
      fi
    done
    if [[ "$success" == "true" ]]; then break; fi
    if [[ "$restart_docker" == "true" ]]; then service docker restart; fi
    sleep 15
  done
}

# The business logic for whether a given object should be created
# was already enforced by salt, and /etc/kubernetes/addons is the
# managed result is of that. Start everything below that directory.
echo "== Kubernetes addon manager started at $(date -Is) with ADDON_CHECK_INTERVAL_SEC=${ADDON_CHECK_INTERVAL_SEC} =="

# Load any images that we may need. This is not needed for trusty master and
# the way it restarts docker daemon does not work for trusty.
if [[ "${trusty_master}" == "false" ]]; then
  load-docker-images /srv/salt/kube-addons-images
fi

ensure_python

# Load the kube-env, which has all the environment variables we care
# about, in a flat yaml format.
kube_env_yaml="/var/cache/kubernetes-install/kube_env.yaml"
if [ ! -e "${kubelet_kubeconfig_file}" ]; then
  eval $(${PYTHON} -c '''
import pipes,sys,yaml

for k,v in yaml.load(sys.stdin).iteritems():
  print("readonly {var}={value}".format(var = k, value = pipes.quote(str(v))))
''' < "${kube_env_yaml}")
fi


# Create the namespace that will be used to host the cluster-level add-ons.
start_addon /etc/kubernetes/addons/namespace.yaml 100 10 "" &

# Wait for the default service account to be created in the kube-system namespace.
token_found=""
while [ -z "${token_found}" ]; do
  sleep .5
  token_found=$(${KUBECTL} get --namespace="${SYSTEM_NAMESPACE}" serviceaccount default -o go-template="{{with index .secrets 0}}{{.name}}{{end}}" || true)
done

echo "== default service account in the ${SYSTEM_NAMESPACE} namespace has token ${token_found} =="

# Generate secrets for "internal service accounts".
# TODO(etune): move to a completely yaml/object based
# workflow so that service accounts can be created
# at the same time as the services that use them.
# NOTE: needs to run as root to read this file.
# Read each line in the csv file of tokens.
# Expect errors when the script is started again.
# NOTE: secrets are created asynchronously, in background.
while read line; do
  # Split each line into the token and username.
  IFS=',' read -a parts <<< "${line}"
  token=${parts[0]}
  username=${parts[1]}
  # DNS is special, since it's necessary for cluster bootstrapping.
  if [[ "${username}" == "system:dns" ]] && [[ ! -z "${KUBERNETES_MASTER_NAME:-}" ]]; then
    create-kubeconfig-secret "${token}" "${username}" "https://${KUBERNETES_MASTER_NAME}"
  else
    # Set the server to https://kubernetes. Pods/components that
    # do not have DNS available will have to override the server.
    create-kubeconfig-secret "${token}" "${username}" "https://kubernetes.default"
  fi
done < "${token_dir}/known_tokens.csv"

# Create admission_control objects if defined before any other addon services. If the limits
# are defined in a namespace other than default, we should still create the limits for the
# default namespace.
for obj in $(find /etc/kubernetes/admission-controls \( -name \*.yaml -o -name \*.json \)); do
  start_addon "${obj}" 100 10 default &
  echo "++ obj ${obj} is created ++"
done

# Create secrets used by appscode addons: icinga, influxdb & daemon
create-appscode-secrets

# Check if the configuration has changed recently - in case the user
# created/updated/deleted the files on the master.
while true; do
  start_sec=$(date +"%s")
  #kube-addon-update.sh must be deployed in the same directory as this file
  `dirname $0`/kube-addon-update.sh /etc/kubernetes/addons ${ADDON_CHECK_INTERVAL_SEC}
  end_sec=$(date +"%s")
  len_sec=$((${end_sec}-${start_sec}))
  # subtract the time passed from the sleep time
  if [[ ${len_sec} -lt ${ADDON_CHECK_INTERVAL_SEC} ]]; then
    sleep_time=$((${ADDON_CHECK_INTERVAL_SEC}-${len_sec}))
    sleep ${sleep_time}
  fi
done
