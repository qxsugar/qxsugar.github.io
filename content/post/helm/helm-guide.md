---
title: "helm3使用分享"
date: "2022-01-04T11:20:20+08:00"
draft: "true"
tags: ["helm"]
categories: ["helm"]
---

## 主题：helm3使用分享

### 背景

    k8s的资源管理目前用的是yaml文件来管理，一般情况下yaml也能满足日常需求，
    但是当我们有很多服务要管理，有很多环境要管理时候，yaml文件很容易变成hard code。
    但是我们期望，一个yaml文件写一次就好了。因为很多行为都是相似的。

### helm介绍

#### 介绍

    helm是简化安装和管理的kubernetes应用的工具。charts是helm应用的具体产物，包括对资源的定义及相关镜像的引用，模版文件，values文件等。
    helm是CNCF的开源项目，目前最新helm已经不需要而外在k8s上安装Tiller了。只需要配置好kubectl config就能使用了。

官网：[https://helm.sh/](https://helm.sh/)
版本：v3.8.0

#### 名词

1. charts，helm包，相关部署文件，values文件的集合
2. release，具体安装的release，用helm list可以查看当前安装的release列表
3. repo，已经发布的helm仓库，包括自己的repo和开源的repo等。
4. hook，helm允许在安装前或者安装后执行一些操作，比如初始化数据库等操作

### helm3模版语法解析

#### 基本语法

基本语法 helm 使用的是

if 语法

with 语法

range 语法

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: "{{ .Release.Name }}-configmap"
data:
  key1: "Hello World"
  key2: "{{ .Values.value2 }}"
```

#### 内置对象

1. `Release` 本次安装的release对象，常用属性
    1. {{ .Release.Name }} 本次安装的releaseName
    2. {{ .Release.Namespace }} 本次安装的命名空间
    3. {{ .Release.IsInstall }} 是否是安装
    4. {{ .Release.IsUpgrade }} 是否是更新
2. `Charts` 对应charts的描述，属性见Charts.yaml
3. `Values` 对应不同环境下的values配置，属性见values.yaml
4. `Files`，`Capabilities` 等

### helm包解析

#### 目录结构

```text
└── app                                             // charts包目录
    ├── Chart.yaml                                  // charts包信息定义，name，type，version等信息
    ├── charts                                      // 依赖的charts
    ├── templates                                   // 模版文件
    │   ├── NOTES.txt                               // helm 执行完成后的信息提示
    │   ├── _helpers.tpl                            // 定义一些公用的模版
    │   ├── deployment.yaml                         // Deployment 模版定义
    │   ├── hpa.yaml                                // HorizontalPodAutoscaler 模版定义
    │   ├── ingress.yaml                            // Ingress 模版定义
    │   ├── service.yaml                            // Service 模版定义
    │   ├── serviceaccount.yaml                     // ServiceAccount 模版定义
    │   └── tests                                   // test 目录
    │       └── test-connection.yaml                // 测试deploy端口是否正常
    └── values.yaml                                 // values定义文件
```

### 应用案例

1. group服务 todo
2. starry-sky-content服务 todo
3. starry-sky-user服务 todo

### helm 常用命令

1. helm list 查看当前安装的release列表
2. helm lint {appName} 对chart包进行lint检查
3. helm install {releaseName} {chartFile} 安装一个名为releaseName的charts包
4. helm delete/uninstall {releaseName} 删除某个release
5. helm upgrade {releaseName} {chartFile} [--set xxx=xxx]

### 注意事项

1. 如果values里面有字典覆盖，结果是字典合并

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

### 参考

1. [https://helm.sh/](https://helm.sh/)
2. [https://whmzsu.github.io/helm-doc-zh-cn/chart_template_guide/index-zh_cn.html](https://whmzsu.github.io/helm-doc-zh-cn/chart_template_guide/index-zh_cn.html)