---
title: "Traefik 源码解读，TCP的完整生命周期"
date: "2022-02-25T18:45:10+08:00"
draft: "false"
tags: ["traefik"]
categories: ["traefik"]
---

下面我们来正式解读traefik源码。

traefik实现了很多协议（tcp，udp等），我们的目标解读一个http请求到了traefik，发送了什么变化，如何被反向代理到目标去。

## Traefik目录结构

traefik 核心代码在cmd目录和pkg目录

```text
pkg
├── api                         # traefik的api实现，比如dashboard api等
├── cli                         # 加载配置
├── collector                   # traefik匿名收集信息
├── config                      # 配置信息
├── healthcheck                 # 对endpoint server做健康检查
├── ip                          # 对ip的一些操作
├── job                         # job任务
├── log                         # log处理
├── metrics                     # 指标处理
├── middlewares                 # traefik内置中间键
├── pilot                       # 链接traefik pilot操作
├── ping                        # ping
├── plugins                     # 插件动态加载和解析
├── provider                    # 提供者，提供endpoint等
├── rules                       # 规则，核心匹配规则
├── safe                        # 关键的goroutine操作
├── server                      # 核心server，包括tcp，udp等server
├── tcp                         # tcp的转换操作
├── tracing                     # 跟踪
├── udp                         # udp的转换操作
```

## 关键接口

```go 
// 这个接口很重要，很多关键操作都是通过这个接口传递的
type Handler interface {
   ServeTCP(conn WriteCloser)
}

// 这个是HTTP层的，作用同上
type Handler interface {
   ServeHTTP(rw http.ResponseWriter, req *http.Request)
}
```

## 代码解读

我们的目标是tcp的流程，所以不关心其他模块的代码了。

### TCP创建

代码启动入口`cmd/traefik/traefik.go`

```go 
// traefik启动最终启动了这个
func runCmd(staticConfiguration *static.Configuration) error {
   // 配置静态配置
   configureLogging(staticConfiguration)
   
   // 创建服务，包括tcp和udp服务
   svr, err := setupServer(staticConfiguration)
	
   // 启动服务，这个方法会启动多个goroutine
   svr.Start(ctx)
}

// 这里生成了tcp和udp的server，放在一个对象里返回
func setupServer(staticConfiguration *static.Configuration) (*server.Server, error) {
   serverEntryPointsTCP, err := server.NewTCPEntryPoints(staticConfiguration.EntryPoints, staticConfiguration.HostResolver)

   serverEntryPointsUDP, err := server.NewUDPEntryPoints(staticConfiguration.EntryPoints)
	
   // 这里会watech动态配置的变更（http.yaml），文件变更会调用switchRouter
   watcher.AddListener(switchRouter(routerFactory, serverEntryPointsTCP, serverEntryPointsUDP, aviator))

   return server.NewServer(routinesPool, serverEntryPointsTCP, serverEntryPointsUDP, watcher, chainBuilder, accessLog), nil
}
```

`NewTCPEntryPoints`方法实现在`pkg/server/server_entrypoint_tcp.go`

```go 
type TCPEntryPoints map[string]*TCPEntryPoint   
// TCPEntryPoints 这个类型是个map的别名，主要是放置多个tcp对象
// 如
//entryPoints:
//  web:
//    address: :80
//  websecure:
//    address: :443
// 这个配置会生成两个tcp监听，监听80和443
// map[web] => 80
// map[websecure] => 443

func NewTCPEntryPoints(entryPointsConfig static.EntryPoints, hostResolverConfig *types.HostResolverConfig) (TCPEntryPoints, error) {
   serverEntryPointsTCP := make(TCPEntryPoints)
   // 这里建立了[web, websecure]的tcp
   for entryPointName, config := range entryPointsConfig {
      serverEntryPointsTCP[entryPointName], err = NewTCPEntryPoint(ctx, config, hostResolverConfig)
   }
   return serverEntryPointsTCP, nil
}
```

`NewTCPEntryPoint`的实现也在`pkg/server/server_entrypoint_tcp.go`

```go 
// NewTCPEntryPoint主要返回TCPEntryPoint对象
func NewTCPEntryPoint(ctx context.Context, configuration *static.EntryPoint, hostResolverConfig *types.HostResolverConfig) (*TCPEntryPoint, error) {
   // 监听tcp
   listener, err := buildListener(ctx, configuration)

   // tcp 路由
   rt := &tcp.Router{}

   reqDecorator := requestdecorator.New(hostResolverConfig)

   // tcp http server
   httpServer, err := createHTTPServer(ctx, listener, configuration, true, reqDecorator)

   rt.HTTPForwarder(httpServer.Forwarder)
    
   // 这里创建了一个tcpSwitcher，这个是实现配置动态更新的核心对象
   tcpSwitcher := &tcp.HandlerSwitcher{}
   tcpSwitcher.Switch(rt)

   return &TCPEntryPoint{
      listener:               listener,
      switcher:               tcpSwitcher,
      transportConfiguration: configuration.Transport,
      tracker:                tracker,
      httpServer:             httpServer,
      httpsServer:            httpsServer,
      http3Server:            h3server,
   }, nil
}
```

到这里基本上traefik已经创建好tcp了。
`Start()`之后就可以请求了，但是这时候配置还没加载进来，所以对于刚刚启动的traefik，请求是返回404的。

### 配置热更新

代码启动入口`cmd/traefik/traefik.go`有个关键代码

```go 
watcher.AddListener(switchRouter(routerFactory, serverEntryPointsTCP, serverEntryPointsUDP, aviator))

// switchRouter 实现
func switchRouter(routerFactory *server.RouterFactory, serverEntryPointsTCP server.TCPEntryPoints, serverEntryPointsUDP server.UDPEntryPoints, aviator *pilot.Pilot) func(conf dynamic.Configuration) {
   return func(conf dynamic.Configuration) {
      // 主要构建了tcp的routers和udp的routers
      routers, udpRouters := routerFactory.CreateRouters(rtConf)
		
      // 这里把重新build后的routers替换了之前的routers，实现了动态配置更新
      serverEntryPointsTCP.Switch(routers)
      serverEntryPointsUDP.Switch(udpRouters)
   }
}
```

`routerFactory.CreateRouters`的实现在`pkg/server/routerfactory.go`

```go 
func (f *RouterFactory) CreateRouters(rtConf *runtime.Configuration) (map[string]*tcpCore.Router, map[string]udpCore.Handler) {
   // service
   serviceManager := f.managerFactory.Build(rtConf)

   // middlewares 
   middlewaresBuilder := middleware.NewBuilder(rtConf.Middlewares, serviceManager, f.pluginBuilder)

   // router
   routerManager := router.NewManager(rtConf, serviceManager, middlewaresBuilder, f.chainBuilder, f.metricsRegistry)

   handlersNonTLS := routerManager.BuildHandlers(ctx, f.entryPointsTCP, false)
   handlersTLS := routerManager.BuildHandlers(ctx, f.entryPointsTCP, true)

   // TCP
   svcTCPManager := tcp.NewManager(rtConf)

   middlewaresTCPBuilder := middlewaretcp.NewBuilder(rtConf.TCPMiddlewares)
    
   rtTCPManager := routertcp.NewManager(rtConf, svcTCPManager, middlewaresTCPBuilder, handlersNonTLS, handlersTLS, f.tlsManager)
   // 主要是这个routersTCP，负责处理TCP请求的router
   routersTCP := rtTCPManager.BuildHandlers(ctx, f.entryPointsTCP)

   return routersTCP, routersUDP
}
```

`BuildHandlers`的实现在`pkg/router/router.go`

```go 
// 这里生成了一个值是tcp.Router的map
func (m *Manager) BuildHandlers(rootCtx context.Context, entryPoints []string) map[string]*tcp.Router {
   entryPointsRouters := m.getTCPRouters(rootCtx, entryPoints)
   entryPointsRoutersHTTP := m.getHTTPRouters(rootCtx, entryPoints, true)

   entryPointHandlers := make(map[string]*tcp.Router)
   for _, entryPointName := range entryPoints {
      entryPointName := entryPointName
      routers := entryPointsRouters[entryPointName]
        
      // 这里返回了一个hanlder，这个就是处理请求的handler
      handler, err := m.buildEntryPointHandler(ctx, routers, entryPointsRoutersHTTP[entryPointName], m.httpHandlers[entryPointName], m.httpsHandlers[entryPointName])

      entryPointHandlers[entryPointName] = handler
   }
   return entryPointHandlers
}

// buildEntryPointHandler 方法实现
func (m *Manager) buildEntryPointHandler(ctx context.Context, configs map[string]*runtime.RouterInfo) (http.Handler, error) {
   router, err := rules.NewRouter()

   for routerName, routerConfig := range configs {
      // 这里调用buildRouterHandler去build一个handler
      handler, err := m.buildRouterHandler(ctxRouter, routerName, routerConfig)
      err = router.AddRoute(routerConfig.Rule, routerConfig.Priority, handler)
   }
    
   // 这里增加一个recovery的middle
   chain := alice.New()
   chain = chain.Append(func(next http.Handler) (http.Handler, error) {
      return recovery.New(ctx, next)
   })

   return chain.Then(router)
}

// buildRouterHandler 方法实现
func (m *Manager) buildRouterHandler(ctx context.Context, routerName string, routerConfig *runtime.RouterInfo) (http.Handler, error) {
       
   // 这里调用 buildHTTPHandler 去获取一个handler对象
   handler, err := m.buildHTTPHandler(ctx, routerConfig, routerName)

   // 这里把handler和其他的合并成一个handler
   handlerWithAccessLog, err := alice.New(func(next http.Handler) (http.Handler, error) {
      return accesslog.NewFieldHandler(next, accesslog.RouterName, routerName, nil), nil
   }).Then(handler)

   return m.routerHandlers[routerName], nil
}

// buildHTTPHandler 实现
func (m *Manager) buildHTTPHandler(ctx context.Context, router *runtime.RouterInfo, routerName string) (http.Handler, error) {
    
   // 这里调用了BuildHTTP获取一个lb
   sHandler, err := m.serviceManager.BuildHTTP(ctx, router.Service)

   // 这里把lb和其他的Middlewares合并成一个chain
   mHandler := m.middlewaresBuilder.BuildChain(ctx, router.Middlewares)

   tHandler := func(next http.Handler) (http.Handler, error) {
      return tracing.NewForwarder(ctx, routerName, router.Service, next), nil
   }

   chain := alice.New()

   if m.metricsRegistry != nil && m.metricsRegistry.IsRouterEnabled() {
      chain = chain.Append(metricsMiddle.WrapRouterHandler(ctx, m.metricsRegistry, routerName, provider.GetQualifiedName(ctx, router.Service)))
   }
   
   return chain.Extend(*mHandler).Append(tHandler).Then(sHandler)
}
```

`BuildHTTP`实现在`pkg/service/service.go`

```go 
func (m *Manager) BuildHTTP(rootCtx context.Context, serviceName string) (http.Handler, error) {
   var lb http.Handler
   switch {
   case conf.LoadBalancer != nil:
      var err error
      // 这里调用getLoadBalancerServiceHandler去获取一个lb
      lb, err = m.getLoadBalancerServiceHandler(ctx, serviceName, conf.LoadBalancer)
   }

   return lb, nil
}

// getLoadBalancerServiceHandler 实现
func (m *Manager) getLoadBalancerServiceHandler(ctx context.Context, serviceName string, service *dynamic.ServersLoadBalancer) (http.Handler, error) {
   roundTripper, err := m.roundTripperManager.Get(service.ServersTransport)

   // 这里返回了ReverseProxy对象
   fwd, err := buildProxy(service.PassHostHeader, service.ResponseForwarding, roundTripper, m.bufferPool)

   alHandler := func(next http.Handler) (http.Handler, error) {
      return accesslog.NewFieldHandler(next, accesslog.ServiceName, serviceName, accesslog.AddServiceFields), nil
   }
   chain := alice.New()
   
   // 这个pipelining对http反向代理做兼容的
   handler, err := chain.Then(pipelining.New(ctx, fwd, "pipelining"))

   // 这里调用了getLoadBalancer去获取一个lb，传入了fwd对象
   balancer, err := m.getLoadBalancer(ctx, serviceName, service, fwd)

   m.balancers[serviceName] = append(m.balancers[serviceName], balancer)

   // emptybackendhandler很有意思，如果找不到有用的服务，就给一个默认的
   return emptybackendhandler.New(balancer), nil
}

func (m *Manager) getLoadBalancer(ctx context.Context, serviceName string, service *dynamic.ServersLoadBalancer, fwd http.Handler) (healthcheck.BalancerStatusHandler, error) {
   // 这里返回了RoundRobin对象，这个对象是实现了ServeHTTP(w http.ResponseWriter, req *http.Request)的
   lb, err := roundrobin.New(fwd, options...)

   return lbsu, nil
}
```

```go 
// RoundRobin是个依赖库，我们看ServeHTTP的核心逻辑
func (r *RoundRobin) ServeHTTP(w http.ResponseWriter, req *http.Request) {
   newReq := *req
	
   if !stuck {
      // 这里获取一个可以用的server的url，然后替换newReq的url
      url, err := r.NextServer()
      // 替换掉新请求的url
      newReq.URL = url
   }
    
   // 这里替换了req，所以当请求到达ReverseProxy层时候，已经可以正确的反向代理了
   r.next.ServeHTTP(w, &newReq)
}
```

### 请求处理

到目前为止，tcp server已经构建部分已经完成了。

我们来看看`pkg/server/server_entrypoint_tcp.go`的`Start`

```go 
func (e *TCPEntryPoint) Start(ctx context.Context) {
   for {
      conn, err := e.listener.Accept()
		
      // 这里对conn做了包装
      writeCloser, err := writeCloser(conn)
	
      safe.Go(func() {
         // 这里的switcer是可以被动态替换的，如果替换了，那么后面的极细就正常了。
         e.switcher.ServeTCP(newTrackedConnection(writeCloser, e.tracker))
      })
   }
}
```

## 预留问题。

1. 域名是如何匹配的？
   > 可以参考`pkg/router/router.go`，`pkg/router/parser.go`
   >
   > parser.go 实现了个树，会通过这棵树来解析匹配。

## 总结

1. traefik 数据传递都是通过`ServeTCP(conn WriteCloser)`和`ServeHTTP(rw http.ResponseWriter, req *http.Request)`来传递的。
2. traefik 自定义插件是通过`yaegi`来动态加载的。
3. alice要先了解原理，否则容易被绕进去。
4. traefik很有很多东西没有解读，插件加载，provider，healthcheck，metrics，udp，tls等都是非常核心的模块。