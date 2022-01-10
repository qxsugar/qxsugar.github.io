---
title: "helm3使用分享"
date: "2022-01-04T11:20:20+08:00"
draft: "true"
tags: ["helm"]
categories: ["helm"]
---

主题：helm3使用分享
------------------

## 背景介绍

helm是一个k8s应用包管理工具，用来更加合理，便捷地管理k8s应用。从helm3版本开始，就不依赖`tiller`了。 也就是说helm3之后的版本，k8s不需要额外安装任何东西，只需要安装了helm3并且配置好kubectl
config就可以使用了。

[开源charts仓库](https://artifacthub.io/)

**helm的本质就是渲染yaml，交给kubectl去执行**

### helm部署和原生yaml文件部署对比

helm的deploy示例

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: { { include "starry-sky-user.fullname" . } }
  labels:
  { { - include "starry-sky-user.labels" . | nindent 4 } }
spec:
  replicas: {{.Values.replicaCount}}
  selector:
    matchLabels:
  { { - include "starry-sky-user.selectorLabels" . | nindent 6 } }

  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 3
  template:
    metadata:
      annotations:
        prometheus.io/should_be_scraped: "true"
        prometheus.io/scrape_port: "8082"
        prometheus.io/app: "{{ .Chart.Name }}"
        prometheus.io/env: "{{ .Values.runEnv }}"
      labels:
    { { - include "starry-sky-user.selectorLabels" . | nindent 8 } }
    spec:
      { { - with .Values.nodeSelector } }
      nodeSelector:
      { { - toYaml . | nindent 8 } }
      { { - end } }
      terminationGracePeriodSeconds: 30
      { { - with .Values.imagePullSecrets } }
      imagePullSecrets:
      { { - toYaml . | nindent 8 } }
      { { - end } }
      securityContext:
      { { - toYaml .Values.podSecurityContext | nindent 8 } }
      containers:
        - name: app
          terminationMessagePath: /dev/termination-log
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{.Values.image.pullPolicy}}
          ports:
            - containerPort: 80
            - containerPort: 8080
          readinessProbe:
            httpGet:
              scheme: HTTP
              path: /ping
              port: 80
            initialDelaySeconds: 5
          livenessProbe:
            httpGet:
              scheme: HTTP
              path: /ping
              port: 80
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 2
          lifecycle:
            preStop:
              exec:
                command: [ "/bin/sh", "-c", "sleep 10" ]
          env:
            { { - toYaml .Values.env | nindent 12 } }
            - name: RUNTIME_ENV
              value: {{.Values.runEnv}}
          { { - with .Values.volumeMounts } }
          volumeMounts:
      { { - toYaml . | nindent 12 } }
      { { - end } }
      { { - with .Values.volumes } }
      volumes:
  { { - toYaml . | nindent 8 } }
  { { - end } }
```

helm对应的values文件

```yaml
replicaCount: 1

image:
  repository: uhub.service.ucloud.cn/unnoo/starry_sky_user_service
  pullPolicy: Always
  tag: "latest"

volumeMounts: { }
volumes: { }

runEnv: product
env:
  - name: foo
    value: bar

imagePullSecrets:
  - name: ucloud-secret
nameOverride: ""
fullnameOverride: ""

podSecurityContext: { }

securityContext: { }

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: false
  className: ""
  annotations: { }
  hosts:
    - host: chart-example.local
      paths:
        - path: /
          pathType: ImplementationSpecific
  tls: [ ]

resources: { }

autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 100
  targetCPUUtilizationPercentage: 80

nodeSelector: { }

tolerations: [ ]

affinity: { }

```

原生yaml文件部署的示例

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: starrysky-user
spec:
  selector:
    matchLabels:
      app: starrysky-user
  replicas: 8
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 3
  template:
    metadata:
      labels:
        app: starrysky-user
      annotations:
        prometheus.io/should_be_scraped: "true"
        prometheus.io/scrape_port: "8088"
        prometheus.io/app: "starrysky-user"
        prometheus.io/env: "product"
    spec:
      terminationGracePeriodSeconds: 30
      imagePullSecrets:
        - name: ucloud-secret

      dnsConfig:
        options:
          - name: ndots
            value: "2"

      containers:
        - name: app
          image: uhub.service.ucloud.cn/unnoo/starry_sky_user_service:latest
          imagePullPolicy: Always
          resources:
            limits:
              cpu: 2000m
              memory: 2Gi
            requests:
              cpu: 100m
              memory: 100Mi
          ports:
            - containerPort: 80
            - containerPort: 8080
          readinessProbe:
            httpGet:
              scheme: HTTP
              path: /ping
              port: 80
            initialDelaySeconds: 5
          livenessProbe:
            httpGet:
              scheme: HTTP
              path: /ping
              port: 80
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 2
          lifecycle:
            preStop:
              exec:
                command: [ "/bin/sh", "-c", "sleep 10" ]
          env:
            - name: GO111MODULE
              value: "on"
            # ...
          volumeMounts:
            - name: logs-volume
              mountPath: /data/logs

      volumes:
        - name: logs-volume
          hostPath:
            path: /data/logs

```

### 优劣势对比

1. 原生yaml文件方式
    - 优势
        - yaml文件编写速度比较快。
        - 调试单个yaml文件比较方便。
    - 劣势
        - 一个服务部署要写多个yaml文件（ingress，service，deployment等），不同环境要写多套yaml文件。
        - 无法复用之前写个的yaml文件，即使99%代码是一样的，也要重写。

2. helm的部署方式
    - 优势
        - 可以复用charts，可以使用别人公开的charts，可以使用公开地charts。
        - 一套charts可以配多个values.yaml适配多个环境。
        - 多个组建打包成一个整体，组件（ingress，service，deployment等）安装一起安装，卸载时候一起卸载。
    - 劣势
        - 需要额外的学习成本。

## 使用方式

### 基本语法

**helm本质上就是模版渲染，使用了`go template`来模版化资源文件，语法和`go template`一致**

1. 在yaml文件里使用变量`{{ .Values.key }}`，如：
   ```
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: "{{ .Release.Name }}-configmap"
   data:
     key1: "Hello World"
   ```

1. with(if)语法，如果条件成立则渲染，如：
   ```
   # 如果配置了.Values.nodeSelector 则吧这个yaml子节点渲染出来
   spec:
      {{- with .Values.nodeSelector }}
      nodeSelector:
      {{- toYaml . | nindent 8 }}
      {{- end }}
   ```
1. range循环语法，对一个列表做循环操作，如：
   ```yaml
   - hosts:
    {{- range .hosts }}
      - {{ . | quote }}
    {{- end }}
      secretName: {{ .secretName }}
   ```
1. include 引入一个模版，如
   ```yaml
   metadata:
     name: {{ $fullName }}
     labels:
       {{ - include "app.labels" . | nindent 4 }}
   ```

### 常用命令

1. helm install {releaseName} {chartFile} --dry-run
1. helm list 查看当前安装的release列表
2. helm lint {appName} 对chart包进行lint检查
3. helm install {releaseName} {chartFile} 安装一个名为releaseName的charts包
4. helm delete/uninstall {releaseName} 删除某个release
5. helm upgrade {releaseName} {chartFile} [--set xxx=xxx]

## charts包剖析

### charts包结构

这是用helm create app 创建的标准模版。

```text
└── app                                             // charts包目录。
    ├── Chart.yaml                                  // charts包信息定义，name，type，version等信息。
    ├── charts                                      // 依赖的charts。
    ├── templates                                   // 模版文件。
    │   ├── NOTES.txt                               // helm 执行完成后的信息提示。
    │   ├── _helpers.tpl                            // 定义一些公用的模版。
    │   ├── deployment.yaml                         // Deployment 模版定义。
    │   ├── hpa.yaml                                // HorizontalPodAutoscaler 模版定义。
    │   ├── ingress.yaml                            // Ingress 模版定义。
    │   ├── service.yaml                            // Service 模版定义。
    │   ├── serviceaccount.yaml                     // ServiceAccount 模版定义。
    │   └── tests                                   // test 目录。
    │       └── test-connection.yaml                // 测试deploy端口是否正常。
    └── values.yaml                                 // values定义文件。
```

### 内置对象

1. `Release` 本次安装的release对象，常用属性。
    1. {{ .Release.Name }} 本次安装的releaseName。
    2. {{ .Release.Namespace }} 本次安装的命名空间。
    3. {{ .Release.IsInstall }} 是否是安装。
    4. {{ .Release.IsUpgrade }} 是否是更新。
2. `Charts` 对应charts的描述，属性见Charts.yaml定义。
3. `Values` 对应不同环境下的values配置，属性见values.yaml。
4. `Files`当前的charts的属性等，`Capabilities` 等。

### 模版定义`_helpers.tpl`

```text
{{/*
Expand the name of the chart.
*/}}
{{- define "app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "app.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "app.labels" -}}
helm.sh/chart: {{ include "app.chart" . }}
{{ include "app.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "app.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
```

## 应用案例

1. [group](https://github.com/unnoo/xmq_addon/tree/develop/kubernetes/helm/group) 服务的test，alpha，beta，product环境。
2. [starry-sky-content](https://github.com/unnoo/xmq_addon/tree/develop/kubernetes/helm/starry-sky-content)
   服务的test，alpha，beta环境。
3. [starry-sky-user](https://github.com/unnoo/xmq_addon/tree/develop/kubernetes/helm/starry-sky-user)
   服务test，alpha，beta环境。

## 注意事项（坑）

1. 如果values里面有字典字段，最终渲染将会是字段合并，相同的key覆盖。

   例如 values.yaml为

    ```yaml
    podAnnotations:
      key1: valu1
      key2: value2
    ```

   prod-values.yaml为

    ```yaml 
    podAnnotations:
      prod-key1: prod-value1
    ```

   最终的渲染结果是

    ```yaml
    annotations:
      key1: valu1
      key2: value2
      prod-key1: prod-value1
    ```

## 更高级功能

1. 可以建立charts仓库，把charts包放在charts仓库使用。
2. charts包可以引用别人的charts包实现复杂的功能。
3. 可以使用tpl函数实现一些复杂的定义。
4. 可以增加钩子操作，实现一些hook操作。
