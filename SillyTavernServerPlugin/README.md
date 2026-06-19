# Tavern Live Bridge 服务端插件

把整个 `SillyTavernServerPlugin` 文件夹复制到 SillyTavern 的：

```text
plugins/tavern-live-bridge
```

然后在 `config.yaml` 中设置：

```yaml
enableServerPlugins: true
```

重启 SillyTavern。浏览器访问下面地址，如果看到 `ok: true` 就安装成功：

```text
http://你的酒馆地址/api/plugins/tavern-live-bridge/health
```

App 会自动把生成请求经过此插件转发，并建立独立随机频道。插件只允许代理 SillyTavern 的生成接口，不接受任意网址。
