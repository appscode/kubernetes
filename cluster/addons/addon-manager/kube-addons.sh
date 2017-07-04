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

# Addons could use this label with two modes:
# - ADDON_MANAGER_LABEL=Reconcile
# - ADDON_MANAGER_LABEL=EnsureExists
ADDON_MANAGER_LABEL="addonmanager.kubernetes.io/mode"
# This label is deprecated (only for Addon Manager). In future release
# addon-manager may not respect it anymore. Addons with
# CLUSTER_SERVICE_LABEL=true and without ADDON_MANAGER_LABEL=EnsureExists
# will be reconciled for now.
CLUSTER_SERVICE_LABEL="kubernetes.io/cluster-service"

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

function create_cluster_metadata() {
  read -r -d '' cfgmapyaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-metadata
  namespace: default
data:
  appscode-ns: ${APPSCODE_NS}
  cluster-uid: ${KUBE_UID}
  cluster-name: ${INSTANCE_PREFIX}
  appscode-cluster-root-domain: ${APPSCODE_CLUSTER_ROOT_DOMAIN}
  appscode-api-grpc-endpoint: ${APPSCODE_API_GRPC_ENDPOINT}
  appscode-api-http-endpoint: ${APPSCODE_API_HTTP_ENDPOINT}
EOF
  create_resource_from_string "${cfgmapyaml}" 100 10 "ConfigMap-for-cluster-metadata" "default" &

  read -r -d '' cfgmapyaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-metadata
  namespace: ${SYSTEM_NAMESPACE}
data:
  appscode-ns: ${APPSCODE_NS}
  cluster-uid: ${KUBE_UID}
  cluster-name: ${INSTANCE_PREFIX}
  appscode-cluster-root-domain: ${APPSCODE_CLUSTER_ROOT_DOMAIN}
  appscode-api-grpc-endpoint: ${APPSCODE_API_GRPC_ENDPOINT}
  appscode-api-http-endpoint: ${APPSCODE_API_HTTP_ENDPOINT}
EOF
  create_resource_from_string "${cfgmapyaml}" 100 10 "ConfigMap-for-cluster-metadata" "${SYSTEM_NAMESPACE}" &
}

function create_hostfacts_secret() {
  local -r name=$1
  local -r safe_name=$(tr -s ':_' '--' <<< "${name}")
  local -r token_base64=$(echo "${HOSTFACTS_AUTH_TOKEN}" | base64 -w0)

  read -r -d '' secretyaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: appscode-${safe_name}
  namespace: ${SYSTEM_NAMESPACE}
type: Opaque
data:
  ca.crt: ${CA_CERT}
  hostfacts.crt: ${HOSTFACTS_CERT}
  hostfacts.key: ${HOSTFACTS_KEY}
  auth_token: ${token_base64}
EOF
  create_resource_from_string "${secretyaml}" 100 10 "Secret-for-${safe_name}" "${SYSTEM_NAMESPACE}" &
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

function create_attic_secret() {
  local tries=$1;
  local -r delay=$2;
  local -r cmd="${KUBECTL} create secret docker-registry attickey --docker-server=docker.appscode.com --docker-username=${APPSCODE_NS}.${APPSCODE_CLUSTER_USER} --docker-password=bearer:${APPSCODE_API_TOKEN} --docker-email=${APPSCODE_CLUSTER_USER}@${APPSCODE_NS}.appscode.io";
  while [ ${tries} -gt 0 ]; do
    echo "${cmd}" | $cmd && \
        echo "== Successfully registered attic secret at $(date -Is)" && \
        return 0;
    let tries=tries-1;
    echo "== Failed to register attic secret at $(date -Is). ${tries} tries remaining. =="
    sleep ${delay};
  done
  return 1;
}

function create_appscode_secrets() {
  if [ -n "$APPSCODE_NS" ] && [ -n "APPSCODE_API_TOKEN" ]; then
    create_cluster_metadata
    if [ -n "$ENABLE_APPSCODE_ATTIC" ]; then
      create_attic_secret 100 10 &
    fi
    read -r -d '' apitoken <<EOF
{
  "namespace":"${APPSCODE_NS}",
  "token":"${APPSCODE_API_TOKEN}"
}
EOF
    create_appscode_secret "${apitoken}" "api-token" "api-token" "${SYSTEM_NAMESPACE}"
  fi

  if [ -n "$DEFAULT_LB_CERT" ] && [ -n "$DEFAULT_LB_KEY" ]; then
    read -r -d '' lbsecretyaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: appscode-default-lb-cert
  namespace: ${SYSTEM_NAMESPACE}
type: Opaque
data:
  tls.crt: ${DEFAULT_LB_CERT}
  tls.key: ${DEFAULT_LB_KEY}
EOF
    create_resource_from_string "${lbsecretyaml}" 100 10 "Secret-for-default-lb-cert" "${SYSTEM_NAMESPACE}" &
  fi

  if [[ "$ENABLE_CLUSTER_VPN" == "h2h-psk" ]]; then
    create_hostfacts_secret "hostfacts"
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
  ${KUBECTL} ${KUBECTL_OPTS} annotate ${obj_type} --namespace=${SYSTEM_NAMESPACE} -l ${CLUSTER_SERVICE_LABEL}=true \
    kubectl.kubernetes.io/last-applied-configuration='' --overwrite=false

  if [[ $? -eq 0 ]]; then
    log INFO "== Annotate resources completed successfully at $(date -Is) =="
  else
    log WRN "== Annotate resources completed with errors at $(date -Is) =="
  fi
}

# $1 enable --prune or not.
function reconcile_addons() {
  local -r enable_prune=$1;

  # TODO: Remove the first command in future release.
  # Adding this for backward compatibility. Old addons have CLUSTER_SERVICE_LABEL=true and don't have
  # ADDON_MANAGER_LABEL=EnsureExists will still be reconciled.
  # Filter out `configured` message to not noisily log.
  # `created`, `pruned` and errors will be logged.
  log INFO "== Reconciling with deprecated label =="
  ${KUBECTL} ${KUBECTL_OPTS} apply --namespace=${SYSTEM_NAMESPACE} -f ${ADDON_PATH} \
    -l ${CLUSTER_SERVICE_LABEL}=true,${ADDON_MANAGER_LABEL}!=EnsureExists \
    --prune=${enable_prune} --recursive | grep -v configured

  log INFO "== Reconciling with addon-manager label =="
  ${KUBECTL} ${KUBECTL_OPTS} apply --namespace=${SYSTEM_NAMESPACE} -f ${ADDON_PATH} \
    -l ${CLUSTER_SERVICE_LABEL}!=true,${ADDON_MANAGER_LABEL}=Reconcile \
    --prune=${enable_prune} --recursive | grep -v configured

  log INFO "== Kubernetes addon reconcile completed at $(date -Is) =="
}

function ensure_addons() {
  # Create objects already exist should fail.
  # Filter out `AlreadyExists` message to not noisily log.
  ${KUBECTL} ${KUBECTL_OPTS} create --namespace=${SYSTEM_NAMESPACE} -f ${ADDON_PATH} \
    -l ${ADDON_MANAGER_LABEL}=EnsureExists --recursive 2>&1 | grep -v AlreadyExists

  log INFO "== Kubernetes addon ensure completed at $(date -Is) =="
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

# Create secrets used by appscode addons: icinga, influxdb & daemon
create_appscode_secrets

# Wait for the default service account to be created in the kube-system namespace.
token_found=""
while [ -z "${token_found}" ]; do
  sleep .5
  token_found=$(${KUBECTL} ${KUBECTL_OPTS} get --namespace="${SYSTEM_NAMESPACE}" serviceaccount default -o go-template="{{with index .secrets 0}}{{.name}}{{end}}")
  if [[ $? -ne 0 ]]; then
    token_found="";
    log WRN "== Error getting default service account, retry in 0.5 second =="
  fi
done

log INFO "== Default service account in the ${SYSTEM_NAMESPACE} namespace has token ${token_found} =="

# Create admission_control objects if defined before any other addon services. If the limits
# are defined in a namespace other than default, we should still create the limits for the
# default namespace.
for obj in $(find /etc/kubernetes/admission-controls \( -name \*.yaml -o -name \*.json \)); do
  start_addon "${obj}" 100 10 default &
  log INFO "++ obj ${obj} is created ++"
done

# TODO: The annotate and spin up parts should be removed after 1.6 is released.

# Fake the "kubectl.kubernetes.io/last-applied-configuration" annotation on old resources
# in order to clean them up by `kubectl apply --prune`.
# RCs have to be annotated for 1.4->1.5+ upgrade, because we migrated from RCs to deployments for all default addons in 1.5.
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
ensure_addons
reconcile_addons false

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
  ensure_addons
  reconcile_addons true
  end_sec=$(date +"%s")
  len_sec=$((${end_sec}-${start_sec}))
  # subtract the time passed from the sleep time
  if [[ ${len_sec} -lt ${ADDON_CHECK_INTERVAL_SEC} ]]; then
    sleep_time=$((${ADDON_CHECK_INTERVAL_SEC}-${len_sec}))
    sleep ${sleep_time}
  fi
done
