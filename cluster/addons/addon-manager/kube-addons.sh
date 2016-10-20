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

# The business logic for whether a given object should be created
# was already enforced by salt, and /etc/kubernetes/addons is the
# managed result is of that. Start everything below that directory.
KUBECTL=${KUBECTL_BIN:-/usr/local/bin/kubectl}
KUBECTL_OPTS=${KUBECTL_OPTS:-}

ADDON_CHECK_INTERVAL_SEC=${TEST_ADDON_CHECK_INTERVAL_SEC:-60}

SYSTEM_NAMESPACE=kube-system
trusty_master=${TRUSTY_MASTER:-false}
addons_dir=${ADDONS_DIR:-/etc/kubernetes/addons}

function create-aws-storageclass() {
  read -r -d '' storage <<EOF
kind: StorageClass
apiVersion: storage.k8s.io/v1beta1
metadata:
  name: io1-100
provisioner: kubernetes.io/aws-ebs
parameters:
  type: io1
  iopsPerGB: "100"
---
kind: StorageClass
apiVersion: storage.k8s.io/v1beta1
metadata:
  name: io1-500
provisioner: kubernetes.io/aws-ebs
parameters:
  type: io1
  iopsPerGB: "500"
---
kind: StorageClass
apiVersion: storage.k8s.io/v1beta1
metadata:
  name: io1-1000
provisioner: kubernetes.io/aws-ebs
parameters:
  type: io1
  iopsPerGB: "1000"
---
kind: StorageClass
apiVersion: storage.k8s.io/v1beta1
metadata:
  name: io1-5000
provisioner: kubernetes.io/aws-ebs
parameters:
  type: io1
  iopsPerGB: "5000"
---
kind: StorageClass
apiVersion: storage.k8s.io/v1beta1
metadata:
  name: io1-10000
provisioner: kubernetes.io/aws-ebs
parameters:
  type: io1
  iopsPerGB: "10000"
---
kind: StorageClass
apiVersion: storage.k8s.io/v1beta1
metadata:
  name: io1-20000
provisioner: kubernetes.io/aws-ebs
parameters:
  type: io1
  iopsPerGB: "20000"
---
kind: StorageClass
apiVersion: storage.k8s.io/v1beta1
metadata:
  name: gp2
provisioner: kubernetes.io/aws-ebs
parameters:
  type: gp2
---
kind: StorageClass
apiVersion: storage.k8s.io/v1beta1
metadata:
  name: st1
provisioner: kubernetes.io/aws-ebs
parameters:
  type: st1
---
kind: StorageClass
apiVersion: storage.k8s.io/v1beta1
metadata:
  name: sc1
provisioner: kubernetes.io/aws-ebs
parameters:
  type: sc1
EOF
  create-resource-from-string "${storage}" 100 10 "StorageClass-for-aws" "default" &
}

function create-gce-storageclass() {
  read -r -d '' storage <<EOF
kind: StorageClass
apiVersion: storage.k8s.io/v1beta1
metadata:
  name: pd-standard
provisioner: kubernetes.io/gce-pd
parameters:
  type: pd-standard
---
kind: StorageClass
apiVersion: storage.k8s.io/v1beta1
metadata:
  name: pd-ssd
provisioner: kubernetes.io/gce-pd
parameters:
  type: pd-ssd
EOF
  create-resource-from-string "${storage}" 100 10 "StorageClass-for-gce" "default" &
}

function activate-extended-ingress() {
  read -r -d '' configyaml <<EOF
metadata:
  name: ingress.appscode.com
apiVersion: extensions/v1beta1
kind: ThirdPartyResource
description: "Extended ingress support for Kubernetes by appscode.com"
versions:
- name: v1
EOF
  create-resource-from-string "${configyaml}" 100 10 "ThirdPartyResource-for-extended-ingress" "default" &
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
  cluster-uid: ${KUBE_UID}
  cluster-name: ${INSTANCE_PREFIX}
  appscode-cluster-root-domain: ${APPSCODE_CLUSTER_ROOT_DOMAIN}
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
  cluster-uid: ${KUBE_UID}
  cluster-name: ${INSTANCE_PREFIX}
  appscode-cluster-root-domain: ${APPSCODE_CLUSTER_ROOT_DOMAIN}
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

function create-artifactory-secret() {
  local tries=$1;
  local -r delay=$2;
  local -r cmd="${KUBECTL} create secret docker-registry artifactorykey --docker-server=docker.appscode.com --docker-username=${APPSCODE_NS}.${APPSCODE_CLUSTER_USER} --docker-password=bearer:${APPSCODE_API_TOKEN} --docker-email=${APPSCODE_CLUSTER_USER}@${APPSCODE_NS}.appscode.io";
  while [ ${tries} -gt 0 ]; do
    echo "${cmd}" | $cmd && \
        echo "== Successfully registered artifactory secret at $(date -Is)" && \
        return 0;
    let tries=tries-1;
    echo "== Failed to register artifactory secret at $(date -Is). ${tries} tries remaining. =="
    sleep ${delay};
  done
  return 1;
}

function create-appscode-secrets() {
  create-cluster-metadata
  create-artifactory-secret 100 10 &

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
  create-appscode-secret "${influx}" "influx" ".admin" "${SYSTEM_NAMESPACE}"
  echo "${influx}" > /srv/influxdb/secrets/.admin

  if [[ "$ENABLE_CLUSTER_SECURITY" == "appscode" ]]; then
    create-ossec-secret "ossec"

    local -r agentyaml=`cat ${addons_dir}/appscode-ossec-wazuh/ossec-agent-daemonset.yaml`
    create-resource-from-string "${agentyaml}" 100 10 "daemonset-for-ossec-agent" "${SYSTEM_NAMESPACE}" &
  fi
}

function create-default-lb() {
  local -r raw_default_lb_cert=$(echo "${DEFAULT_LB_CERT}" | base64 --decode)
  local -r raw_default_lb_key=$(echo "${DEFAULT_LB_KEY}" | base64 --decode)

  read -r -d '' lbpem <<EOF
${raw_default_lb_cert}
${raw_default_lb_key}
EOF
  create-appscode-secret "${lbpem}" "default-lb-cert" "tls.pem" "appscode"

  local -r default_lb_host=${INSTANCE_PREFIX}-${APPSCODE_NS}.${APPSCODE_CLUSTER_ROOT_DOMAIN}
  read -r -d '' engress <<EOF
{
  "apiVersion": "appscode.com/v1",
  "kind": "Ingress",
  "metadata": {
    "name": "default-lb",
    "namespace": "appscode",
    "annotations": {
      "lb.appscode.com/type": "Daemon",
      "lb.appscode.com/daemon.hostname": "$(hostname)"
    }
  },
  "spec": {
    "rules": [
      {
        "host": "${default_lb_host}",
        "http": {
          "paths": [
            {
              "path": "/icingaweb2",
              "backend": {
                "serviceName": "appscode-alert.kube-system",
                "servicePort": "80"
              }
            }
          ]
        }
      },
      {
        "host": "${default_lb_host}",
        "http": {
          "paths": [
            {
              "path": "/kibana",
              "backend": {
                "serviceName": "kibana-logging.kube-system",
                "servicePort": "5601"
              }
            }
          ]
        }
      },
      {
        "host": "${default_lb_host}",
        "tcp": [
          {
            "backend": {
              "serviceName": "monitoring-influxdb.kube-system",
              "servicePort": "8083"
            },
            "pemName": "tls.pem",
            "port": "8083",
            "secretName": "appscode-default-lb-cert"
          },
          {
            "backend": {
              "serviceName": "monitoring-influxdb.kube-system",
              "servicePort": "8086"
            },
            "pemName": "tls.pem",
            "port": "8086",
            "secretName": "appscode-default-lb-cert"
          }
        ]
      },
      {
        "host": "${default_lb_host}",
        "tcp": [
          {
            "backend": {
              "serviceName": "appscode-alert.kube-system",
              "servicePort": "5665"
            },
            "port": "5665"
          }
        ]
      }
    ],
    "tls": [
      {
        "hosts": [
          "${default_lb_host}"
        ],
        "secretName": "appscode-default-lb-cert"
      }
    ]
  }
}
EOF

  local tries=100;
  local -r delay=10;
  # curl -v -H "Content-Type: application/json" -X POST -d "${engress}" http://localhost:8080/apis/appscode.com/v1/namespaces/appscode/ingresses && \
  while [ ${tries} -gt 0 ]; do
    [[ `curl -s -o /dev/null -w "%{http_code}" -H "Content-Type: application/json" -X POST -d "${engress}" http://localhost:8080/apis/appscode.com/v1/namespaces/appscode/ingresses` = '200' ]] && \
        echo "== Successfully created default lb engress at $(date -Is)" && \
        return 0;
    let tries=tries-1;
    echo "== Failed to create default lb engress at $(date -Is). ${tries} tries remaining. =="
    sleep ${delay};
  done
  return 1;
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
    echo "${config_string}" | ${KUBECTL} ${KUBECTL_OPTS} --namespace="${namespace}" apply -f - && \
        echo "== Successfully started ${config_name} in namespace ${namespace} at $(date -Is)" && \
        return 0;
    let tries=tries-1;
    echo "== Failed to start ${config_name} in namespace ${namespace} at $(date -Is). ${tries} tries remaining. =="
    sleep ${delay};
  done
  return 1;
}

# The business logic for whether a given object should be created
# was already enforced by salt, and /etc/kubernetes/addons is the
# managed result is of that. Start everything below that directory.
echo "== Kubernetes addon manager started at $(date -Is) with ADDON_CHECK_INTERVAL_SEC=${ADDON_CHECK_INTERVAL_SEC} =="

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

# Wait for the default service account to be created in the kube-system namespace.
token_found=""
while [ -z "${token_found}" ]; do
  sleep .5
  token_found=$(${KUBECTL} ${KUBECTL_OPTS} get --namespace="${SYSTEM_NAMESPACE}" serviceaccount default -o go-template="{{with index .secrets 0}}{{.name}}{{end}}" || true)
done

echo "== default service account in the ${SYSTEM_NAMESPACE} namespace has token ${token_found} =="

# Create admission_control objects if defined before any other addon services. If the limits
# are defined in a namespace other than default, we should still create the limits for the
# default namespace.
for obj in $(find /etc/kubernetes/admission-controls \( -name \*.yaml -o -name \*.json \)); do
  start_addon "${obj}" 100 10 default &
  echo "++ obj ${obj} is created ++"
done

if [ "$PROVIDER" = "aws" ]; then
    create-aws-storageclass &
elif [ "$PROVIDER" = "gce" ]; then
    create-gce-storageclass &
fi

# Activate Extended Ingress to allow TCP loadbalancing
activate-extended-ingress

# Create secrets used by appscode addons: icinga, influxdb & daemon
create-appscode-secrets

# Create default load balancer to expose cluster apps
create-default-lb &

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
