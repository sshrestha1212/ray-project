# Ray Project Deploy From RayService

## What’s a RayService?
A RayService manages these components:

- RayCluster: Manages resources in a Kubernetes cluster.

- Ray Serve Applications: Manages users’ applications.

## What does the RayService provide?

- Kubernetes-native support for Ray clusters and Ray Serve applications: After using a Kubernetes configuration to define a Ray cluster and its Ray Serve applications, you can use kubectl to create the cluster and its applications.

- In-place updating for Ray Serve applications: See RayService for more details.

- Zero downtime upgrading for Ray clusters: See RayService for more details.

- High-availabilable services: See RayService high availability for more details.

### Preparation
- Install kubectl (>= 1.23), Helm (>= v3.4) if needed, Kind, and Docker.
- Make sure your Kubernetes cluster has at least 4 CPU and 4 GB RAM.

## Step 1: Create a Kubernetes cluster

This step creates a local Kubernetes cluster using Kind. If you already have a Kubernetes cluster, you can skip this step.

``` 
kind create cluster --image=kindest/node:v1.26.0
```

## Step 2: Deploy a KubeRay operator

Deploy the KubeRay operator with the Helm chart repository .

```
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm repo update

# Install both CRDs and KubeRay operator v1.3.0.
helm install kuberay-operator kuberay/kuberay-operator --version 1.3.0

# Confirm that the operator is running in the namespace `default`.
kubectl get pods
# NAME                                READY   STATUS    RESTARTS   AGE
# kuberay-operator-7fbdbf8c89-pt8bk   1/1     Running   0          27s
```


## Step 3 Package Your Python File

If we have a Python file locally and want to deploy it using RayService, we need to package your Python file (or module) and its dependencies so that it can be used in the Ray cluster. Here's how we can do it step by step:

- If your Python file has dependencies, create a requirements.txt file listing all the dependencies.

- If your Python file is part of a larger module, ensure it has a proper package structure .

### Example structure:

```
my_app/
├── summarize.py
├── requirements.txt
```


## Step 4: Create a Docker Image

To deploy your local Python file, you need to create a Docker image that includes your code and dependencies.

Create a Dockerfile in the same directory:

```
# Use the official Ray image as the base
FROM rayproject/ray:2.41.0

WORKDIR /app

# Copy your application code
COPY summarize.py /app
COPY requirements.txt /app

RUN pip install -r requirements.txt
```
### Build the Docker image:

```bash
docker build -t my-ray-app:latest .
```
### Push the Docker image to a container registry (e.g., Docker Hub):

```bash
docker tag my-ray-app:latest <your-dockerhub-username>/my-ray-app:latest
docker push <your-dockerhub-username>/my-ray-app:latest
```
## Step 5: Create a RayService YAML File

Define your Ray cluster and Serve application in a YAML file. Use the Docker image you created.

```
apiVersion: ray.io/v1
kind: RayService
metadata:
  name: rayservice-sample
spec:
  serveConfigV2: |
    applications:
      - name: app
        import_path: summarize:app
        route_prefix: /
        runtime_env:
           pip: ["torch", "transformers", "fastapi"]
        deployments:
          - name: Translator
            num_replicas: 2
            ray_actor_options:
              num_cpus: 0.2
          - name: Summarizer
            num_replicas: 1
            ray_actor_options:
              num_cpus: 0.2
  rayClusterConfig:
    rayVersion: '2.41.0' # should match the Ray version in the image of the containers
    ######################headGroupSpecs#################################
    # Ray head pod template.
    headGroupSpec:
      rayStartParams: {}
      #pod template
      template:
        spec:
          containers:
            - name: ray-head
              image: <your-dockerhub-username>/ray-serve:latest
              ports:
                - containerPort: 6379
                  name: gcs-server
                - containerPort: 8265 # Ray dashboard
                  name: dashboard
                - containerPort: 10001
                  name: client
                - containerPort: 8000
                  name: serve
                - containerPort: 44217
                  name: as-metrics # autoscaler
                - containerPort: 44227
                  name: dash-metrics # dashboard
              resources:
                limits:
                  cpu: "1"
                  memory: "2G"
                requests:
                  cpu: "1"
                  memory: "2G"
    workerGroupSpecs:
      # the pod replicas in this group typed worker
      - replicas: 1
        minReplicas: 1
        maxReplicas: 5
        groupName: small-group
        rayStartParams: {}
        #pod template
        template:
          spec:
            containers:
              - name: ray-worker # must consist of lower case alphanumeric characters or '-', and must start and end with an alphanumeric character (e.g. 'my-name',  or '123-abc'
                image: <your-dockerhub-username>/ray-serve:latest
                resources:
                  limits:
                    cpu: "1"
                    memory: "2Gi"
                  requests:
                    cpu: "500m"
                    memory: "2Gi"
```
### Key Points:

- The image field in rayClusterConfig points to your custom Docker image.

- The import_path in serveConfigV2 points to your Python file and the Serve app (summarize:app).


## Step 6: Verify the Kubernetes cluster status


```
# Step 4.1: List all RayService custom resources in the `default` namespace.
kubectl get rayservice

# [Example output]
# NAME                SERVICE STATUS   NUM SERVE ENDPOINTS
# rayservice-sample   Running          1

# Step 4.2: List all RayCluster custom resources in the `default` namespace.
kubectl get raycluster

# [Example output]
# NAME                                 DESIRED WORKERS   AVAILABLE WORKERS   CPUS    MEMORY   GPUS   STATUS   AGE
# rayservice-sample-raycluster-bwrp8   1                 1                   2500m   4Gi      0      ready    83s

# Step 4.3: List all Ray Pods in the `default` namespace.
kubectl get pods -l=ray.io/is-ray-node=yes

# [Example output]
# NAME                                                          READY   STATUS    RESTARTS   AGE
# rayservice-sample-raycluster-bwrp8-head-p8dnc                 1/1     Running   0          105s
# rayservice-sample-raycluster-bwrp8-small-group-worker-hbwr2   1/1     Running   0          105s

# Step 4.4: Check the `Ready` condition of the RayService.
# The RayService is ready to serve requests when the condition is `True`.
kubectl describe rayservices.ray.io rayservice-sample

# [Example output]
# Conditions:
#   Last Transition Time:  2025-02-13T04:55:37Z
#   Message:               Number of serve endpoints is greater than 0
#   Observed Generation:   1
#   Reason:                NonZeroServeEndpoints
#   Status:                True
#   Type:                  Ready

# Step 4.5: List services in the `default` namespace.
kubectl get services

# NAME                                          TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                                                   AGE
# ...
# rayservice-sample-head-svc                    ClusterIP   None           <none>        10001/TCP,8265/TCP,6379/TCP,8080/TCP,8000/TCP   77s
# rayservice-sample-raycluster-bwrp8-head-svc   ClusterIP   None           <none>        10001/TCP,8265/TCP,6379/TCP,8080/TCP,8000/TCP   2m16s
# rayservice-sample-serve-svc                   ClusterIP   10.96.212.79   <none>        8000/TCP                                        77s
```

## Step 7: Verify the status of the Serve applications

```
kubectl port-forward svc/rayservice-sample-head-svc 8265:8265
```

## Step8: Access the Serve application:

- Port-forward the HTTP service:
```
kubectl port-forward svc/rayservice-example-head-svc 8000:8000
```

client.py file looks like to test serve application

```
import requests

english_text = (
    "It was the best of times, it was the worst of times, it was the age "
    "of wisdom, it was the age of foolishness, it was the epoch of belief"
)
response = requests.post("http://127.0.0.1:8000/", json=english_text)
french_text = response.text

print(french_text)
```

- Test the application by running:

```
python3 client.py

##Output
c'était le meilleur des temps, c'était le pire des temps .
```


## Step9: Update or Scale the Deployment

To update your application, rebuild the Docker image, push it to the registry, and update the image field in the rayservice.yaml file. Then reapply the YAML:

```
kubectl apply -f ray-service.yaml
```
## Step 10: Clean Up

To delete the RayService and associated resources:

```
kubectl delete -f ray-service.yaml