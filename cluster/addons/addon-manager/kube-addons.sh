#!/bin/bash

# Copyright 2014 The Kubernetes Authors.
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

# LIMITATIONS
# 1. Exit code is probably not always correct.
# 2. There are no unittests.
# 3. Will not work if the total length of paths to addons is greater than
#    bash can handle. Probably it is not a problem: ARG_MAX=2097152 on GCE.

# cosmetic improvements to be done
# 1. Improve the log function; add timestamp, file name, etc.
# 2. Logging doesn't work from files that print things out.
# 3. Kubectl prints the output to stderr (the output should be captured and then
#    logged)

# The business logic for whether a given object should be created
# was already enforced by salt, and /etc/kubernetes/addons is the
# managed result is of that. Start everything below that directory.
KUBECTL=${KUBECTL_BIN:-/usr/local/bin/kubectl}
KUBECTL_OPTS=${KUBECTL_OPTS:-}

ADDON_CHECK_INTERVAL_SEC=${TEST_ADDON_CHECK_INTERVAL_SEC:-60}
ADDON_PATH=${ADDON_PATH:-/etc/kubernetes/addons}

SYSTEM_NAMESPACE=kube-system

# Remember that you can't log from functions that print some output (because
# logs are also printed on stdout).
# $1 level
# $2 message
function log() {
  # manage log levels manually here

  # add the timestamp if you find it useful
  case $1 in
    DB3 )
#        echo "$1: $2"
        ;;
    DB2 )
#        echo "$1: $2"
        ;;
    DBG )
#        echo "$1: $2"
        ;;
    INFO )
        echo "$1: $2"
        ;;
    WRN )
        echo "$1: $2"
        ;;
    ERR )
        echo "$1: $2"
        ;;
    * )
        echo "INVALID_LOG_LEVEL $1: $2"
        ;;
  esac
}

# $1 command to execute.
# $2 count of tries to execute the command.
# $3 delay in seconds between two consecutive tries
function run_until_success() {
  local -r command=$1
  local tries=$2
  local -r delay=$3
  local -r command_name=$1
  while [ ${tries} -gt 0 ]; do
    log DBG "executing: '$command'"
    # let's give the command as an argument to bash -c, so that we can use
    # && and || inside the command itself
    /bin/bash -c "${command}" && \
      log DB3 "== Successfully executed ${command_name} at $(date -Is) ==" && \
      return 0
    let tries=tries-1
    log WRN "== Failed to execute ${command_name} at $(date -Is). ${tries} tries remaining. =="
    sleep ${delay}
  done
  return 1
}

function create_appscode_secret() {
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
  create_resource_from_string "${secretyaml}" 100 10 "Secret-for-${safe_name}" "${namespace}" &
}

function create_icinga_secret() {
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
ICINGA_K8S_SERVICE=appscode-icinga.kube-system
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
  create_resource_from_string "${secretyaml}" 100 10 "Secret-for-${safe_name}" "${SYSTEM_NAMESPACE}" &
}

function create_appscode_secrets() {
  if [ -n "$APPSCODE_NS" ] && [ -n "APPSCODE_API_TOKEN" ]; then
    read -r -d '' apitoken <<EOF
{
  "namespace":"${APPSCODE_NS}",
  "token":"${APPSCODE_API_TOKEN}"
}
EOF
    mkdir -p /var/run/secrets/appscode
    echo "${apitoken}" > /var/run/secrets/appscode/api-token
    create_appscode_secret "${apitoken}" "api-token" "api-token" "${SYSTEM_NAMESPACE}"
  fi

  if [ "$ENABLE_CLUSTER_ALERT" = "appscode" ]; then
    create_icinga_secret
  fi

  if [ "$ENABLE_CLUSTER_MONITORING" = "appscode" ]; then
    read -r -d '' influx <<EOF
INFLUX_HOST=monitoring-influxdb
INFLUX_API_PORT=8086
INFLUX_DB=k8s
INFLUX_ADMIN_USER=${APPSCODE_INFLUX_ADMIN_USER}
INFLUX_ADMIN_PASSWORD=${APPSCODE_INFLUX_ADMIN_PASSWORD}
INFLUX_READ_USER=${APPSCODE_INFLUX_READ_USER}
INFLUX_READ_PASSWORD=${APPSCODE_INFLUX_READ_PASSWORD}
INFLUX_WRITE_USER=${APPSCODE_INFLUX_WRITE_USER}
INFLUX_WRITE_PASSWORD=${APPSCODE_INFLUX_WRITE_PASSWORD}
EOF
    create_appscode_secret "${influx}" "influx" ".admin" "${SYSTEM_NAMESPACE}"
  fi
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

  create_resource_from_string "$(cat ${addon_filename})" "${tries}" "${delay}" "${addon_filename}" "${namespace}"
}

# $1 string with json or yaml.
# $2 count of tries to start the addon.
# $3 delay in seconds between two consecutive tries
# $4 name of this object to use when logging about it.
# $5 namespace for this object
function create_resource_from_string() {
  local -r config_string=$1;
  local tries=$2;
  local -r delay=$3;
  local -r config_name=$4;
  local -r namespace=$5;
  while [ ${tries} -gt 0 ]; do
    echo "${config_string}" | ${KUBECTL} ${KUBECTL_OPTS} --namespace="${namespace}" apply -f - && \
      log INFO "== Successfully started ${config_name} in namespace ${namespace} at $(date -Is)" && \
      return 0;
    let tries=tries-1;
    log WRN "== Failed to start ${config_name} in namespace ${namespace} at $(date -Is). ${tries} tries remaining. =="
    sleep ${delay};
  done
  return 1;
}

# $1 resource type.
function annotate_addons() {
  local -r obj_type=$1;

  # Annotate to objects already have this annotation should fail.
  # Only try once for now.
  ${KUBECTL} ${KUBECTL_OPTS} annotate ${obj_type} --namespace=${SYSTEM_NAMESPACE} -l kubernetes.io/cluster-service=true \
    kubectl.kubernetes.io/last-applied-configuration='' --overwrite=false

  if [[ $? -eq 0 ]]; then
    log INFO "== Annotate resources completed successfully at $(date -Is) =="
  else
    log WRN "== Annotate resources completed with errors at $(date -Is) =="
  fi
}

# $1 enable --prune or not.
# $2 additional option for command.
function update_addons() {
  local -r enable_prune=$1;
  local -r additional_opt=$2;

  run_until_success "${KUBECTL} ${KUBECTL_OPTS} apply --namespace=${SYSTEM_NAMESPACE} -f ${ADDON_PATH} \
    --prune=${enable_prune} -l kubernetes.io/cluster-service=true --recursive ${additional_opt}" 3 5

  if [[ $? -eq 0 ]]; then
    log INFO "== Kubernetes addon update completed successfully at $(date -Is) =="
  else
    log WRN "== Kubernetes addon update completed with errors at $(date -Is) =="
  fi
}

# The business logic for whether a given object should be created
# was already enforced by salt, and /etc/kubernetes/addons is the
# managed result is of that. Start everything below that directory.
log INFO "== Kubernetes addon manager started at $(date -Is) with ADDON_CHECK_INTERVAL_SEC=${ADDON_CHECK_INTERVAL_SEC} =="

# Load the kube-env, which has all the environment variables we care
# about, in a flat yaml format.
kube_env_yaml="/var/cache/kubernetes-install/kube_env.yaml"
if [ -e "${kube_env_yaml}" ]; then
  eval "$(python -c '
import pipes,sys,yaml

for k,v in yaml.load(sys.stdin).iteritems():
  print("""readonly {var}={value}""".format(var = k, value = pipes.quote(str(v))))
  print("""export {var}""".format(var = k))
  ' < """${kube_env_yaml}""")"
fi
env | sort

# Create the namespace that will be used to host the cluster-level add-ons.
start_addon /opt/namespace.yaml 100 10 "" &

# Wait for the default service account to be created in the appscode namespace.
token_found=""
while [ -z "${token_found}" ]; do
  sleep .5
  token_found=$(${KUBECTL} ${KUBECTL_OPTS} get --namespace=appscode serviceaccount default -o go-template="{{with index .secrets 0}}{{.name}}{{end}}")
  if [[ $? -ne 0 ]]; then
    token_found="";
    log WRN "== Error getting default service account, retry in 0.5 second =="
  fi
done

log INFO "== Default service account in the appscode namespace has token ${token_found} =="

# Create admission_control objects if defined before any other addon services. If the limits
# are defined in a namespace other than default, we should still create the limits for the
# default namespace.
for obj in $(find /etc/kubernetes/admission-controls \( -name \*.yaml -o -name \*.json \)); do
  start_addon "${obj}" 100 10 default &
  log INFO "++ obj ${obj} is created ++"
done

# Create secrets used by appscode addons: icinga, influxdb & daemon
create_appscode_secrets

# Fake the "kubectl.kubernetes.io/last-applied-configuration" annotation on old resources
# in order to clean them up by `kubectl apply --prune`.
# RCs have to be annotated for 1.4->1.5 upgrade, because we are migrating from RCs to deployments for all default addons.
# Other types resources will also need this fake annotation if their names are changed,
# otherwise they would be leaked during upgrade.
log INFO "== Annotating the old addon resources at $(date -Is) =="
annotate_addons ReplicationController
annotate_addons Deployment

# Create new addon resources by apply (with --prune=false).
# The old RCs will not fight for pods created by new Deployments with the same label because the `controllerRef` feature.
# The new Deployments will not fight for pods created by old RCs with the same label because the additional `pod-template-hash` label.
# Apply will fail if some fields are modified but not are allowed, in that case should bump up addon version and name (e.g. handle externally).
log INFO "== Executing apply to spin up new addon resources at $(date -Is) =="
update_addons false

# Wait for new addons to be spinned up before delete old resources
log INFO "== Wait for addons to be spinned up at $(date -Is) =="
sleep ${ADDON_CHECK_INTERVAL_SEC}

# Start the apply loop.

# Check if the configuration has changed recently - in case the user
# created/updated/deleted the files on the master.
log INFO "== Entering periodical apply loop at $(date -Is) =="
while true; do
  start_sec=$(date +"%s")
  # Only print stderr for the readability of logging
  update_addons true ">/dev/null"
  end_sec=$(date +"%s")
  len_sec=$((${end_sec}-${start_sec}))
  # subtract the time passed from the sleep time
  if [[ ${len_sec} -lt ${ADDON_CHECK_INTERVAL_SEC} ]]; then
    sleep_time=$((${ADDON_CHECK_INTERVAL_SEC}-${len_sec}))
    sleep ${sleep_time}
  fi
done
