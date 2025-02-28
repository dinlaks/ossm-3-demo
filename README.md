# ossm-3-demo
OpenShift Service Mesh 3 Demo/Quckstart with Gateway API for ingress.

## For Red Hatters
Use the following demo:
[AWS with OpenShift Open Environment](https://catalog.demo.redhat.com/catalog?item=babylon-catalog-prod/sandboxes-gpte.sandbox-ocp.prod)

Minimal OCP config:
- Control Plane Count: `1`
- Control Plane Instance Type: `m6a.4xlarge` (resources to handle OSSM and observability overhead)


# Quickstart: OSSM3 with Kiali, Tempo, Bookinfo
- Based off of https://github.com/mkralik3/sail-operator/tree/quickstart/docs/ossm/quickstarts/ossm3-kiali-tempo-bookinfo
  
  
This quickstart guide provides step-by-step instructions on how to set up OSSM3 with Kiali, Tempo, Open Telemetry, and Bookinfo app. It also includes an example of using the next generation of ingress with the Kuberntetes Gateway API to access an example RestAPI.  
  
By the end of this quickstart, you will have installed OSSM3, where tracing information is collected by Open Telemetry Collector and Tempo, and monitoring is managed by an in-cluster monitoring stack. The Bookinfo sample application will be included in the service mesh, with a traffic generator sending one request per second to simualte traffic. Additionally, the Kiali UI and OSSMC plugin will be set up to provide a graphical overview.

***Note: Bookinfo uses the istio gateway for ingress. The RestAPI uses Kubernetes Gateway API for ingress***

## Prerequisites
- The OpenShift Service Mesh 3, Kiali, Tempo, Red Hat build of OpenTelemetry operators have been installed (you can install it by `./install_operators.sh` script which installs the particular operator versions (see subscriptions.yaml))
- The above listed script also enables the `Gateway API`, which will be included with OCP in a future release (TBD)
- The cluster that has available Persistent Volumes or supports dynamic provisioning storage (for installing MiniO)
- You are logged into OpenShift via the CLI

## What is located where
The quickstart 
  * installs MiniO and Tempo to `tracing-system` namespace
  * installs OpenTelemetryCollector to `opentelemetrycollector` namespace
  * installs OSSM3 (Istio CR) with Kiali and OSSMC to `istio-system` namespace
  * installs IstioCNI to `istio-cni` namespace
  * installs Istio ingress gateway to `istio-ingress` namespace
  * installs Gateway API ingress gateway to `istio-ingress` namespace
  * installs bookinfo app with traffic generator in `bookinfo` namespace
  * installs RestAPI app in `rest-api-with-mesh` namespace

## Shortcut to the end
To skip all the following steps and set everything up automatically (e.g., for demo purposes), simply run the prepared `./install_ossm3_demo.sh` script which will perform all steps automatically.

## Steps
All required YAML resources are in the `./resources` folder.
For a more detailed description about what is set and why, see OpenShift Service Mesh documentation.

## Demo Setup Plan
In this demo, I m going to walkthrough how the OSSM 3 is configured and managed finally with examples showcasing the service mesh management:

## Install the following OpenShift Operators:
1. OpenShift Service Mesh 3 (Tech Preview)
2. Kiali
3. OpenTelemetry
4. Tempo


## Gateways 
The Sail Operator does not deploy Ingress or Egress Gateways. Gateways are not part of the control plane. As a security best-practice, Ingress and Egress Gateways should be deployed in a different namespace than the namespace that contains the control plane.

You can deploy gateways using either the Gateway API(TP) or Gateway Injection methods.

### Option 1: Istio Gateway Injection
Gateway Injection uses the same mechanisms as Istio sidecar injection to create a gateway from a Deployment resource that is paired with a Service resource that can be made accessible from outside the cluster. For more information, see Installing Gateways. We will use this method for the ```bookinfo``` application later.  

### Option 2: Kubernetes Gateway API
Istio includes support for Kubernetes Gateway API and intends to make it the default API for traffic management in the future. For more information, see Istio's Kubernetes Gateway API page. Istio includes support for Kubernetes Gateway API and intends to make it the default API for traffic management in the future. Gateway API is Kubernetes’ next generation standard for service networking. A more flexible API than Kubernetes Ingress that includes service mesh features such as traffic management. Provide consistent APIs across Kubernetes Ingress and Service Mesh. Istio APIs will continue to be supported.

Its a gateway controller similar to Istio API provides. But, offers more rich features supporting both L4 and L7 protocols. Overall, Gateways define a whole new way of declaring and managing traffic targeting Kubernetes services that avoids the limitations teams experience using only Ingress resources. The Gateway API creates a standardized model for enabling features like L4 support, advanced HTTP routing, and built-in traffic management in a portable fashion across all compliant gateway controllers. This will prevent vendor lock-in and give developers expanded declarative management without having to touch low-level controller configurations.  

## Enable Gateway API (Kubernetes Gateway API CRDs are not available by default and must be enabled to be used) 
Enable Gateway API  (only if you did not run the `./install_operators.sh` script)
------------  
```bash
oc get crd gateways.gateway.networking.k8s.io &> /dev/null ||  { oc kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v1.0.0" | oc apply -f -; }
```

## Implement an OpenShift Service Mesh solution:
1. Provision and configure OpenShift Service Mesh control plane and other Istio supporting components (CRs and namespaces):
2. Istio (istiod)
3. Istio-CNI (pod networking)
4. Ingress-Gateway (for Gateway API and Istio Gateway)

Set up OSSM3
------------
```bash
oc new-project istio-system
```
First, install Istio custom resource
> **_NOTE:_**  In this example, the `.spec.version` is missing so the istio version is automatically set by OSSM operator. You can specify the version manually, but it must be one that is supported by the operator; otherwise, a validation error will occur.
```bash
oc apply -f ./resources/OSSM3/istiocr.yaml  -n istio-system
oc wait --for condition=Ready istio/default --timeout 60s  -n istio-system
```

Then, install IstioCNI
> **_NOTE:_**  In this example, the `.spec.version` is missing so the istio version is automatically set by OSSM operator. the `.spec.version` is missing so the istio version is automatically set by OSSM operator. You can specify the version manually, but it must be one that is supported by the operator.
```bash
oc new-project istio-cni
oc apply -f ./resources/OSSM3/istioCni.yaml -n istio-cni
oc wait --for condition=Ready istiocni/default --timeout 60s -n istio-cni
```

Set up the ingress gateway via istio in a different namespace as istio-system.
Add that namespace as a member of the mesh.
```bash
oc new-project istio-ingress
oc label namespace istio-ingress istio-injection=enabled
oc apply -f ./resources/OSSM3/istioIngressGateway.yaml  -n istio-ingress
oc wait --for condition=Available deployment/istio-ingressgateway --timeout 60s -n istio-ingress
```
Expose Istio ingress route which will be used in the bookinfo traffic generator later (and via that URL, we will be accessing to the bookinfo app)
```bash
oc expose svc istio-ingressgateway --port=http2 --name=istio-ingressgateway -n istio-ingress
```
Set up the ingress gateway via Gateway API (this will live next to the previously created gateway in the same namespace)
```bash
oc apply -k ./resources/gateway
```

## Set up Tempo and OpenTelemetryCollector  
Provision and configure a tracing-system via a TempoStack for distributed tracing:
1. MinIO for persistent S3 storage
2. Tempo
3. OpenTelemetry CRs:
4. OpenTelemetryCollector

Telemetry
------------  
```bash
oc new-project tracing-system
```
First, set up MiniO storage which is used by Tempo to store data (or you can use S3 storage, see Tempo documentation)
```bash
oc apply -f ./resources/TempoOtel/minio.yaml -n tracing-system
oc wait --for condition=Available deployment/minio --timeout 150s -n tracing-system
```
Then, set up Tempo CR
```bash
oc apply -f ./resources/TempoOtel/tempo.yaml -n tracing-system
oc wait --for condition=Ready TempoStack/sample --timeout 150s -n tracing-system
oc wait --for condition=Available deployment/tempo-sample-compactor --timeout 150s -n tracing-system
```
Expose Jaeger UI route which will be used in the Kiali CR later
```bash
oc expose svc tempo-sample-query-frontend --port=jaeger-ui --name=tracing-ui -n tracing-system
```
Next, set up OpenTelemetryCollector
```bash
oc new-project opentelemetrycollector
oc apply -f ./resources/TempoOtel/opentelemetrycollector.yaml -n opentelemetrycollector
oc wait --for condition=Available deployment/otel-collector --timeout 60s -n opentelemetrycollector
```
Then, set up Telemetry resource to enable tracers defined in Istio custom resource
```bash
oc apply -f ./resources/TempoOtel/istioTelemetry.yaml  -n istio-system
```
The opentelemetrycollector namespace needs to be added as a member of the mesh
```bash
oc label namespace opentelemetrycollector istio-injection=enabled
```
> **_NOTE:_** `istio-injection=enabled` label works only when the name of Istio CR is `default`. If you use a different name as `default`, you need to use `istio.io/rev=<istioCR_NAME>` label instead of `istio-injection=enabled` in the all next steps of this example. Also, you will need to update values `config_map_name`, `istio_sidecar_injector_config_map_name`, `istiod_deployment_name`, `url_service_version` in the Kiali CR.

## Set up Kiali & OpenShift Service Mesh Console Plugin
------------
Create cluster role binding for kiali to be able to read ocp monitoring
```bash
oc apply -f ./resources/Kiali/kialiCrb.yaml -n istio-system
```
Set up Kiali CR. The URL for Jaeger UI (which was exposed earlier) needs to be set to Kiali CR in `.spec.external_services.tracing.url`
> **_NOTE:_**  In this example, the `.spec.version` is missing so the istio version is automatically set by Kiali operator. You can specify the version manually, but it must be one that is supported by the operator; otherwise, an error will appear in events on the Kiali resource.
```bash
export TRACING_INGRESS_ROUTE="http://$(oc get -n tracing-system route tracing-ui -o jsonpath='{.spec.host}')"
cat ./resources/Kiali/kialiCr.yaml | JAEGERROUTE="${TRACING_INGRESS_ROUTE}" envsubst | oc -n istio-system apply -f -
oc wait --for condition=Successful kiali/kiali --timeout 150s -n istio-system 
```
Increase timeout for the Kiali ui route in OCP since big queries for spans can take longer
```bash
oc annotate route kiali haproxy.router.openshift.io/timeout=60s -n istio-system
```
Optionally, OSSMC plugin can be installed as well
> **_NOTE:_**  In this example, the `.spec.version` is missing so the istio version is automatically set by Kiali operator. You can specify the version manually, but it must be one that is supported by the operator and the version needs to be **the same as Kiali CR**.
```bash
oc apply -f ./resources/Kiali/kialiOssmcCr.yaml -n istio-system
oc wait -n istio-system --for=condition=Successful OSSMConsole ossmconsole --timeout 120s
```

## Monitoring Configuration:
1. Enable User Monitoring with OpenShift Observability (Prometheus).
2. Enable SystemMonitor in the istio-system namespace.
3. Enable PodMonitor in all Istio-related namespaces as well as application namespaces:
   3a. istio-system
   3b. istio-ingress
   3c. bookinfo
   3d. rest-api-with-mesh
4. Label all Istio-related and application namespaces with istio-injection=enabled.

Set up OCP user monitoring workflow
------------
First, OCP user monitoring needs to be enabled
```bash
oc apply -f ./resources/Monitoring/ocpUserMonitoring.yaml
```
Then, create service monitor and pod monitor for istio namespaces
```bash
oc apply -f ./resources/Monitoring/serviceMonitor.yaml -n istio-system
oc apply -f ./resources/Monitoring/podMonitor.yaml -n istio-system
oc apply -f ./resources/Monitoring/podMonitor.yaml -n istio-ingress
```

## Sample Applications for Demo and Use Cases:
### bookinfo: A sample multi-service application to demonstrate OSSM observability.

Set up BookInfo
------------
Create bookinfo namespace and add that namespace as a member of the mesh
```bash
oc new-project bookinfo
oc label namespace bookinfo istio-injection=enabled
```
Create pod monitor for bookinfo namespaces
```bash
oc apply -f ./resources/Monitoring/podMonitor.yaml -n bookinfo
```
> **_NOTE(shortcut):_**  It takes some time till pod monitor shows in Metrics targets, you can check it in OCP console Observe->Targets. The Kiali UI will not show the metrics till the targets are ready.
 
Install the Bookinfo app (the bookinfo resources are from `release-1.23` istio release branch)
```bash
oc apply -f ./resources/Bookinfo/bookinfo.yaml -n bookinfo
oc apply -f ./resources/Bookinfo/bookinfo-gateway.yaml -n bookinfo
oc wait --for=condition=Ready pods --all -n bookinfo --timeout 60s
```

Optionally, install a traffic generator for booking app which every second generates a request to simulate traffic
```bash
export INGRESSHOST=$(oc get route istio-ingressgateway -n istio-ingress -o=jsonpath='{.spec.host}')
cat ./resources/Bookinfo/traffic-generator-configmap.yaml | ROUTE="http://${INGRESSHOST}/productpage" envsubst | oc -n bookinfo apply -f - 
oc apply -f ./resources/Bookinfo/traffic-generator.yaml -n bookinfo
```


## rest-api-with-mesh: 
A simple RestAPI application containing a front-end API that calls our back-end API, deployed via Canary deployment.

Set up sample RestAPI    
------------  

Install the sample RestAPI `hello-service` via Kustomize
```bash
oc apply -k ./resources/application/kustomize/overlays/pod 
```

## Validation
Test that everything works correctly
------------
Now, everything should be set.  

Check the Bookinfo app via the ingress route
```bash
INGRESSHOST=$(oc get route istio-ingressgateway -n istio-ingress -o=jsonpath='{.spec.host}')
echo "http://${INGRESSHOST}/productpage"
```
  
Check the RestAPI
```bash
export GATEWAY=$(oc get gateway hello-gateway -n istio-ingress -o template --template='{{(index .status.addresses 0).value}}')

curl -s $GATEWAY/hello | jq
curl -s $GATEWAY/hello-service | jq
```

Check Kiali UI
```bash
KIALI_HOST=$(oc get route kiali -n istio-system -o=jsonpath='{.spec.host}')
echo "https://${KIALI_HOST}"
```
You can check all namespaces that all pods running correctly:
```bash
oc get pods -n tracing-system
oc get pods -n opentelemetrycollector
oc get pods -n istio-system
oc get pods -n istio-cni
oc get pods -n istio-ingress
oc get pods -n bookinfo
oc get pods -n rest-api-with-mesh    
```
Output (the number of istio-cni pods is equals to the number of OCP nodes):
```bash
NAME                                           READY   STATUS    RESTARTS   AGE
minio-6f8c5c79-fmjpd                           1/1     Running   0          10m
tempo-sample-compactor-dcffd76dc-7mnll         1/1     Running   0          10m
tempo-sample-distributor-7dbbf4b5d7-xw5w5      1/1     Running   0          10m
tempo-sample-ingester-0                        1/1     Running   0          10m
tempo-sample-querier-7bbcc6dd9b-gtl4q          1/1     Running   0          10m
tempo-sample-query-frontend-5885fff6bf-cklc5   2/2     Running   0          10m

NAME                              READY   STATUS    RESTARTS   AGE
otel-collector-77b6b4b58d-dwk6q   1/1     Running   0          9m23s

NAME                           READY   STATUS    RESTARTS   AGE
istiod-6847b886d5-s8vz8        1/1     Running   0          9m8s
kiali-6b7dbdf67b-cczm5         1/1     Running   0          7m56s
ossmconsole-7b64979c75-f9fbf   1/1     Running   0          7m22s

NAME                   READY   STATUS    RESTARTS   AGE
istio-cni-node-8h4mr   1/1     Running   0          8m44s
istio-cni-node-qvmw4   1/1     Running   0          8m44s
istio-cni-node-vpv9v   1/1     Running   0          8m44s
istio-cni-node-wml9b   1/1     Running   0          8m44s
istio-cni-node-x8np2   1/1     Running   0          8m44s

NAME                                    READY   STATUS    RESTARTS   AGE
hello-gateway-istio-8449867f56-zsqk5    1/1     Running   0          33m
istio-ingressgateway-7f8878b6b4-bq64q   1/1     Running   0          32m
istio-ingressgateway-7f8878b6b4-d7m5p   1/1     Running   0          33m

NAME                             READY   STATUS    RESTARTS   AGE
details-v1-65cfcf56f9-72k5p      2/2     Running   0          3m4s
kiali-traffic-generator-cblht    2/2     Running   0          77s
productpage-v1-d5789fdfb-rlkhl   2/2     Running   0          3m
ratings-v1-7c9bd4b87f-5qmmp      2/2     Running   0          3m3s
reviews-v1-6584ddcf65-mhd75      2/2     Running   0          3m2s
reviews-v2-6f85cb9b7c-q8mc2      2/2     Running   0          3m2s
reviews-v3-6f5b775685-ctb65      2/2     Running   0          3m1s

NAME                            READY   STATUS    RESTARTS   AGE
service-b-v1-6c8c645587-krn87   2/2     Running   0          31m
service-b-v2-68f956ddc6-v62jf   2/2     Running   0          31m
web-front-end-9446fc49d-t8zh7   2/2     Running   0          31m
```
