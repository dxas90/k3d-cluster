SHELL=/usr/bin/env bash -o pipefail
export SELF ?= $(MAKE)
DOCKER := $(shell which docker)
ENVSUBST := $(shell which envsubst)
K3D := $(shell which k3d)
KUBECTL := $(shell which kubectl)
MKDIR := $(shell which mkdir)

RAND := $(shell date +%s | sha256sum | base64 | head -c 32 ; echo)

export CLUSTER_NAME ?= k3s
export ISSUER_EMAIL ?= yourname@gmail.com
export DEFAULT_IFACE := $(shell ip route | grep "default" | head -n 1 | cut -d ' ' -f 5)
export CURRENT_IP := $(shell ip addr show ${DEFAULT_IFACE}  | grep "inet " | cut -d '/' -f 1 | cut -d 't' -f 2 | tr -d ' ' | head -n 1)
export CURRENT_EXTERNAL_IP := $(shell curl -sS ipinfo.io | jq ".ip" | tr -d '\"')
export SHARED_PATH ?= ${HOME}/projects
export LATEST_K3S_VERSION := $(shell curl -sL https://api.github.com/repos/k3s-io/k3s/releases/latest | jq -r ".tag_name")
export K3S_VERSION ?= $(shell echo ${LATEST_K3S_VERSION/+/-})

define assert-set
	@[ -n "$($1)" ] || (echo "$(1) not defined in $(@)"; exit 1)
endef

all: k8s

k8s: create/cluster \
	install/storage \
	install/kube-vip \
	install/loadbalancer \
	install/monitoring \
	install/certmanager \
	install/loadbalancer-fix
	@echo -e "\\033[1;32mCleanning cluster ${CLUSTER_NAME} events\\033[0;39m"
	@$(KUBECTL) delete events --all --all-namespaces

clean: delete/cluster

create/cluster:
	$(call assert-set,CLUSTER_NAME)
	$(call assert-set,CURRENT_IP)
	$(call assert-set,SHARED_PATH)
	@echo -e "\\033[1;32mCreating cluster ${CLUSTER_NAME} with ${SHARED_PATH} as a shared path\\033[0;39m"
	@$(MKDIR) -p ${SHARED_PATH}/default-local-pv
	@$(ENVSUBST) < k3d-config.yaml | cat > /tmp/k3d-config.yaml
	@$(K3D) cluster list --no-headers | grep ${CLUSTER_NAME} > /dev/null 2>&1 || $(K3D) cluster create -c /tmp/k3d-config.yaml

delete/cluster:
	$(call assert-set,CLUSTER_NAME)
	@echo -e "\\033[1;32mDeleting cluster ${CLUSTER_NAME}\\033[0;39m"
	@$(K3D) cluster delete ${CLUSTER_NAME}

install/certmanager: create/cluster
	$(call assert-set,KUBECTL)
	@echo -e "\\033[1;32mInstalling cert-manager\\033[0;39m"
	@$(KUBECTL) apply -f https://github.com/jetstack/cert-manager/releases/download/v1.17.2/cert-manager.yaml
	@$(KUBECTL) -n cert-manager wait --for condition=available --timeout=90s deploy -lapp.kubernetes.io/instance=cert-manager
	@$(ENVSUBST) < k8s/02_certmanager-resources.yaml | $(KUBECTL) apply -f -

install/loadbalancer: install/kube-vip
	$(call assert-set,KUBECTL)
	@echo -e "\\033[1;32mInstalling traefik\\033[0;39m"
	@$(KUBECTL) apply -f k8s/03_traefik/00_gateway_crd.yml
	@$(KUBECTL) apply -f k8s/03_traefik/00_traefik_crd.yml
	@$(ENVSUBST) < k8s/03_traefik/01_traefik_workload.yaml | cat > /tmp/01_traefik_workload.yaml
	@$(KUBECTL) apply -f /tmp/01_traefik_workload.yaml

install/loadbalancer-fix: install/loadbalancer
	$(call assert-set,KUBECTL)
	@echo -e "\\033[1;32mFixing traefik deployment\\033[0;39m"
	@$(eval export INGRESSENDPOINT := $(shell $(KUBECTL) get service -n infrastructure traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}'))
	@$(KUBECTL) patch deploy traefik -n infrastructure -p '[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--providers.kubernetesingress.ingressendpoint.ip=${INGRESSENDPOINT}"}]' --type json

install/kong: install/kube-vip
	$(call assert-set,KUBECTL)
	@echo -e "\\033[1;32mInstalling kong\\033[0;39m"
	@$(KUBECTL) apply -Rf k8s/03_kong

install/kube-vip: create/cluster
	$(call assert-set,KUBECTL)
	@echo -e "\\033[1;32mInstalling kube-vip\\033[0;39m"
	@$(eval export GLOBAL_CIDR_RANGE := $(shell $(DOCKER) network inspect k3d-${CLUSTER_NAME} | jq '.[0].IPAM.Config[0].Subnet'| tr -d '"'))
	@$(eval export START_RANGE := $(shell echo ${GLOBAL_CIDR_RANGE} |sed 's/0\/.*/200/g'))
	@$(eval export END_RANGE := $(shell echo ${GLOBAL_CIDR_RANGE}  |sed 's/0\/.*/254/g'))
	@$(KUBECTL) get configmap --namespace kube-system kubevip > /dev/null 2>&1 || kubectl create configmap --namespace kube-system kubevip --from-literal range-global=${START_RANGE}-${END_RANGE}
	@$(KUBECTL) apply -f https://kube-vip.io/manifests/rbac.yaml
	@$(KUBECTL) apply -f https://raw.githubusercontent.com/kube-vip/kube-vip-cloud-provider/main/manifest/kube-vip-cloud-controller.yaml
	@$(KUBECTL) apply -f k8s/kube-vip-daemonset.yaml

install/metallb: create/cluster
	$(call assert-set,KUBECTL)
	@echo -e "\\033[1;32mInstalling metallb\\033[0;39m"
	@$(eval export CIDR_RANGE := $(shell $(DOCKER) network inspect k3d-${CLUSTER_NAME} | jq '.[0].IPAM.Config[0].Subnet'|sed 's/0/200/g'| tr -d '"'))
	@$(eval export START_RANGE := $(shell echo ${CIDR_RANGE}  |sed 's/200\/.*/240/g'))
	@$(eval export END_RANGE := $(shell echo ${CIDR_RANGE}  |sed 's/200\/.*/254/g'))
	@$(KUBECTL) apply -k github.com/metallb/metallb/config/native?ref=v0.13.10
	@$(KUBECTL) get secret -n metallb-system memberlist > /dev/null 2>&1 || $(KUBECTL) create secret generic -n metallb-system memberlist --from-literal=secretkey="$(shell openssl rand -base64 128)" > /dev/null 2>&1
	@$(KUBECTL) -n metallb-system wait --for condition=available --timeout=120s deployment.apps/controller
	@$(KUBECTL) -n metallb-system wait --for=jsonpath='{.status.numberMisscheduled}'=0 --timeout=120s daemonset.apps/speaker
	@$(ENVSUBST) < k8s/01_metallb_resources.yaml | $(KUBECTL) apply -f -

install/monitoring: install/storage
	$(call assert-set,KUBECTL)
	@echo -e "\\033[1;32mInstalling Prometheus, metrics-server and kube-state-metrics\\033[0;39m"
	@$(KUBECTL) apply -f k8s/monitoring/00_metrics-server.yaml
	@$(KUBECTL) apply -f https://github.com/prometheus-operator/prometheus-operator/releases/download/v0.67.1/stripped-down-crds.yaml
	@$(KUBECTL) apply -f k8s/monitoring/01_monitoring.yaml
	@$(KUBECTL) apply -Rf k8s/monitoring/02_kube-state-metrics
	@$(KUBECTL) apply -f k8s/monitoring/02_monitoring_prometheus_alertmanager.yaml

install/storage: create/cluster
	$(call assert-set,KUBECTL)
	@echo -e "\\033[1;32mInstalling local-path-storage\\033[0;39m"
	@$(KUBECTL) apply -f k8s/00_local-path-storage.yaml

install/external-secrets: install/storage
	$(call assert-set,KUBECTL)
	@echo -e "\\033[1;32mInstalling External Secrets operator\\033[0;39m"
	@$(KUBECTL) apply -f k8s/10_external-secrets.yml

install/cockroach: install/storage
	$(call assert-set,KUBECTL)
	@echo -e "\\033[1;32mInstalling cockroach\\033[0;39m"
	@$(KUBECTL) -n cockroach-operator-system apply -f https://raw.githubusercontent.com/cockroachdb/cockroach-operator/v2.10.0/install/crds.yaml
	@$(KUBECTL) -n cockroach-operator-system apply -f https://raw.githubusercontent.com/cockroachdb/cockroach-operator/v2.10.0/install/operator.yaml
	@$(KUBECTL) -n cockroach-operator-system wait --for condition=available --timeout=90s deploy -lapp=cockroach-operator ; $(shell sleep 5)
	@$(KUBECTL) -n infrastructure apply -f k8s/99_cockroach.yaml

install/redis: install/storage
	$(call assert-set,KUBECTL)
	@echo -e "\\033[1;32mInstalling redis\\033[0;39m"
	@$(KUBECTL) -n infrastructure apply -f k8s/04_redis.yml

install/redis-cluster: install/storage
	$(call assert-set,KUBECTL)
	@echo -e "\033[1;32mInstalling redis (you might have to run this twice)\033[0;39m"
	@$(KUBECTL) -n infrastructure apply -f k8s/04_full-redis-cluster.yml
	@$(KUBECTL) -n infrastructure wait --for=jsonpath='{.status.availableReplicas}'=6 --timeout=120s statefulset.apps/redis-cluster
	@echo -e "\033[1;32mChecking redis (you might have to run this twice)\033[0;39m"
	@echo -e "\033[1;33mError 99 is that Redis cluster is up and running\033[0;39m"
	@test "$(shell kubectl -n infrastructure exec -it redis-cluster-0 --container redis -- redis-cli cluster info|grep cluster_state:|cut -d ":" -f 2 |tr -d "\r")" = "ok" &&  exit 99 || exit 0
	@echo "yes" | $(KUBECTL) -n infrastructure exec -it redis-cluster-0 -- redis-cli --cluster create --cluster-replicas 1 $(shell kubectl -n infrastructure get pods -l app=redis-cluster -o jsonpath='{range.items[*]}{.status.podIP}:6379 {end}')

install/postgres: install/storage
	$(call assert-set,KUBECTL)
	@echo -e "\033[1;32mInstalling postgres\033[0;39m"
	@$(eval export MASTER_PASSWORD := $(shell < /dev/urandom tr -dc A-Za-z0-9\- | head -c18; echo))
	@$(eval export REPLICA_PASSWORD := $(shell < /dev/urandom tr -dc A-Za-z0-9\- | head -c18; echo))
	@$(KUBECTL) -n infrastructure get secrets postgres > /dev/null 2>&1 || $(ENVSUBST) < k8s/00_postgres/00_secret.tmpl | $(KUBECTL) -n infrastructure apply -f -
	@$(KUBECTL) -n infrastructure get configmaps postgres > /dev/null 2>&1 || $(KUBECTL) -n infrastructure create configmap postgres --from-file=k8s/00_postgres/config/postgres.conf --from-file=k8s/00_postgres/config/master.conf --from-file=k8s/00_postgres/config/replica.conf --from-file=k8s/00_postgres/config/pg_hba.conf --from-file=k8s/00_postgres/config/create-replica-user.sh
	@$(KUBECTL) -n infrastructure apply -f k8s/00_postgres/00_config.yml -f k8s/00_postgres/00_master-statefulset.yml -f k8s/00_postgres/01_service-statefulset.yml
	@$(KUBECTL) -n infrastructure wait --for=jsonpath='{.status.readyReplicas}'=1 --timeout=120s statefulsets.apps/postgres
	@$(KUBECTL) -n infrastructure apply -f k8s/00_postgres

install/mongodb: install/storage
	$(call assert-set,KUBECTL)
	@echo -e "\033[1;32mInstalling mongodb\033[0;39m"
	@$(KUBECTL) -n infrastructure apply -f k8s/05_mongodb

install/minio: install/storage
	$(call assert-set,KUBECTL)
	@echo -e "\033[1;32mInstalling MinIO\033[0;39m"
	@$(KUBECTL) -n infrastructure apply -f k8s/09_minio

install/nats: install/storage
	$(call assert-set,KUBECTL)
	@echo -e "\033[1;32mInstalling Nats\033[0;39m"
	@$(KUBECTL) -n infrastructure apply -f k8s/01_nats

.PHONY: \
	all
