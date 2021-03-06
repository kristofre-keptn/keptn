#!/bin/bash
JENKINS_URL=$1
JENKINS_USER=$2
JENKINS_PASSWORD=$3
REGISTRY_URL=$4

kubectl create namespace keptn

kubectl label namespace keptn istio-injection=enabled

# Install knative serving, eventing, build
kubectl apply --filename https://github.com/knative/serving/releases/download/v0.3.0/serving.yaml
kubectl apply --filename https://github.com/knative/build/releases/download/v0.3.0/release.yaml
kubectl apply --filename https://github.com/knative/eventing/releases/download/v0.3.0/release.yaml
kubectl apply --filename https://github.com/knative/eventing-sources/releases/download/v0.3.0/release.yaml
kubectl apply --filename https://github.com/knative/serving/releases/download/v0.3.0/monitoring.yaml

# Configure knative serving default domain
rm -f ../manifests/gen/config-domain.yaml

export ISTIO_INGRESS_IP=$(kubectl describe svc istio-ingressgateway -n istio-system | grep "LoadBalancer Ingress:" | sed 's~LoadBalancer Ingress:[ \t]*~~')
cat ../manifests/knative/config-domain.yaml | \
  sed 's~ISTIO_INGRESS_IP_PLACEHOLDER~'"$ISTIO_INGRESS_IP"'~' >> ../manifests/gen/config-domain.yaml

kubectl apply -f ../manifests/gen/config-domain.yaml

# Install kaniko build template
kubectl apply -f https://raw.githubusercontent.com/knative/build-templates/master/kaniko/kaniko.yaml -n keptn

# Create build-bot service account
kubectl apply -f ../manifests/knative/build/service-account.yaml

kubectl create secret generic -n keptn jenkinsurl --from-literal=jenkinsurl="http://$JENKINS_USER:$JENKINS_PASSWORD@jenkins.cicd.svc.cluster.local:24711"

# Mark internal docker registry as insecure registry for knative controller
val=$(kubectl -n knative-serving get cm config-controller -o=json | jq -r .data.registriesSkippingTagResolving | awk '{print $1",'$REGISTRY_URL':5000"}')
kubectl -n knative-serving get cm config-controller -o=yaml | yq w - data.registriesSkippingTagResolving $val | kubectl apply -f -

# Deploy knative eventing channel (keptn-channel)
kubectl apply -f ../../core/eventbroker/config/channel.yaml
export KEPTN_CHANNEL_URI=$(kubectl describe channel keptn-channel -n keptn | grep "Hostname:" | sed 's~[ \t]*Hostname:[ \t]*~~')

kubectl apply -f ../../core/eventbroker/config/new-artefact-channel.yaml
export NEW_ARTEFACT_CHANNEL=$(kubectl describe channel new-artefact -n keptn | grep "Hostname:" | sed 's~[ \t]*Hostname:[ \t]*~~')

kubectl apply -f ../../core/eventbroker/config/start-deployment-channel.yaml
export START_DEPLOYMENT_CHANNEL=$(kubectl describe channel start-deployment -n keptn | grep "Hostname:" | sed 's~[ \t]*Hostname:[ \t]*~~')

kubectl apply -f ../../core/eventbroker/config/deployment-finished-channel.yaml
export DEPLOYMENT_FINISHED_CHANNEL=$(kubectl describe channel deployment-finished -n keptn | grep "Hostname:" | sed 's~[ \t]*Hostname:[ \t]*~~')

kubectl apply -f ../../core/eventbroker/config/start-tests-channel.yaml
export START_TESTS_CHANNEL=$(kubectl describe channel start-tests -n keptn | grep "Hostname:" | sed 's~[ \t]*Hostname:[ \t]*~~')

kubectl apply -f ../../core/eventbroker/config/tests-finished-channel.yaml
export TESTS_FINISHED_CHANNEL=$(kubectl describe channel tests-finished -n keptn | grep "Hostname:" | sed 's~[ \t]*Hostname:[ \t]*~~')

kubectl apply -f ../../core/eventbroker/config/start-evaluation-channel.yaml
export START_EVALUATION_CHANNEL=$(kubectl describe channel start-evaluation -n keptn | grep "Hostname:" | sed 's~[ \t]*Hostname:[ \t]*~~')

kubectl apply -f ../../core/eventbroker/config/evaluation-done-channel.yaml
export EVALUATION_DONE_CHANNEL=$(kubectl describe channel evaluation-done -n keptn | grep "Hostname:" | sed 's~[ \t]*Hostname:[ \t]*~~')

# Deploy event broker
cd ../../core/eventbroker
./deploy.sh $REGISTRY_URL $KEPTN_CHANNEL_URI $NEW_ARTEFACT_CHANNEL $START_DEPLOYMENT_CHANNEL $DEPLOYMENT_FINISHED_CHANNEL $START_TESTS_CHANNEL $TESTS_FINISHED_CHANNEL $START_EVALUATION_CHANNEL $EVALUATION_DONE_CHANNEL
cd ../../install/scripts

# Deploy Operator
# kubectl apply -f ../../keptn.jenkins-operator/config/operator.yaml