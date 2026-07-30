# Android Native Binder 完整架构设计文档

## 目录

1. [概述](#1-概述)
2. [架构总览](#2-架构总览)
3. [核心组件](#3-核心组件)
4. [通信流程](#4-通信流程)
5. [接口定义层](#5-接口定义层)
6. [Client 端代理](#6-client-端代理)
7. [Server 端实现](#7-server-端实现)
8. [ServiceManager](#8-servicemanager)
9. [线程模型](#9-线程模型)
10. [内存管理](#10-内存管理)
11. [安全机制](#11-安全机制)
12. [实战模板](#12-实战模板)

---

## 1. 概述

Binder 是 Android 特有的 IPC 机制，基于 **C/S 架构**，通过 `/dev/binder` 设备节点与内核交互。相比传统 Socket/管道，Binder：

| 特性 | Binder | Socket | 管道 |
|------|--------|--------|------|
| 性能 | 一次拷贝 | 两次拷贝 | 两次拷贝 |
| 编程模型 | 同步调用 | 异步消息 | 异步消息 |
| 服务发现 | 内置 | 需额外实现 | 不支持 |
| 死亡通知 | 原生支持 | 需额外实现 | 不支持 |

---

## 2. 架构总览

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Client Process                                │
│                                                                         │
│  ┌──────────┐    ┌──────────────┐    ┌────────────────────────────┐   │
│  │  App     │───►│  BpProxy      │───►│  Parcel                   │   │
│  │  Code    │◄───│  (transact)   │◄───│  (序列化/反序列化)        │   │
│  └──────────┘    └──────────────┘    └────────────────────────────┘   │
│                                                                         │
│         └── android::sp<IService>  (智能指针，refcount)                  │
└─────────────────────────────────┼───────────────────────────────────────┘
                                  │  transact()
┌─────────────────────────────────▼───────────────────────────────────────┐
│                          Kernel Space                                   │
│                                                                         │
│                      ┌─────────────────┐                               │
│                      │   Binder Driver │                               │
│                      │   /dev/binder    │                               │
│                      │                  │                               │
│                      │  - transaction   │                               │
│                      │  - BC_REPLY      │                               │
│                      │  - BC_FREE_BUFFER│                               │
│                      │  - BC_INCREFS    │                               │
│                      │  - ...           │                               │
│                      └─────────────────┘                               │
│                                  │                                      │
└──────────────────────────────────┼──────────────────────────────────────┘
                                   │
┌──────────────────────────────────▼──────────────────────────────────────┐
│                           Server Process                                │
│                                                                         │
│  ┌──────────────────────────────────────────────────────┐              │
│  │              BBinder / BnInterface                    │              │
│  │                                                       │              │
│  │  onTransact() ──► 根据 code 分发到具体方法             │              │
│  └──────────────────────────────────────────────────────┘              │
│                              │                                          │
│  ┌───────────────────────────▼────────────────────────────┐              │
│  │              Service (MyService)                       │              │
│  │                                                       │              │
│  │  queryInfo() / sendData() / ...  (业务逻辑)            │              │
│  └───────────────────────────────────────────────────────┘              │
│                                                                         │
│  ┌──────────────┐      ┌────────────────────────────────────┐          │
│  │  Service     │◄────►│  ServiceManager                    │          │
│  │  Manager     │      │  (系统服务，0xdead1234)            │          │
│  └──────────────┘      └────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 3. 核心组件

### 3.1 IBinder — 底层接口

```cpp
// 所有 binder 对象实现此接口
class IBinder {
    // 发送 transact，阻塞等待 reply
    virtual status_t transact(
        uint32_t code,           // 命令码
        const Parcel& data,      // 请求数据
        Parcel* reply,           // 回复数据
        uint32_t flags = 0       // FLAG_ONEWAY 等
    ) = 0;

    // 引用计数
    virtual void incStrong(const void* id) = 0;
    virtual void decStrong(const void* id) = 0;

    // 死亡通知
    virtual void linkToDeath(const wp<DeathRecipient>& recipient) = 0;
};
```

### 3.2 BpBinder — Client 端 Binder 引用

```cpp
// BpBinder 是 IBinder 的客户端实现
//持有远程 binder 的句柄 (handle)
class BpBinder : public IBinder {
    int mHandle;  // handle to remote binder
    // transact() 最终调用 ioctl(mHandle, BINDER_WRITE_READ, ...)
};
```

### 3.3 BBinder — Server 端 Binder 基类

```cpp
// BBinder 是 IBinder 的服务端实现
// onTransact() 分发事务到具体服务
class BBinder : public IBinder {
    virtual status_t onTransact(
        uint32_t code,
        const Parcel& data,
        Parcel* reply,
        uint32_t flags
    ) = 0;

    // transact() 默认实现: 解析 data，调用 onTransact()
};
```

### 3.4 IInterface — 业务接口基类

```cpp
// 业务接口需继承此模板
template<typename INTERFACE>
class IInterface {
public:
    static const android::String16& descriptor;
    static INTERFACE* asInterface(const sp<IBinder>& obj);
protected:
    virtual INTERFACE* asInterface() = 0;
};
```

### 3.5 Parcel — 数据容器

```cpp
// binder 通信的数据打包格式
class Parcel {
    // 写入基本类型
    status_t writeInt32(int32_t val);
    status_t writeString16(const String16& str);
    status_t writeBinder(const sp<IBinder>& val);

    // 读取基本类型
    int32_t readInt32();
    String16 readString16();
    sp<IBinder> readBinder();

    // 文件描述符传递 (通过 SCM_RIGHTS)
    status_t writeFileDescriptor(int fd);
    int readFileDescriptor();
};
```

---

## 4. 通信流程

### 4.1 完整时序图

```
Client                                              Server
   │                                                   │
   │  1. getService("my.service")                     │
   │───────────► ServiceManager ─────────────────────►│
   │              (查找并返回 binder 引用)              │
   │◄────────────  BpBinder(handle=123) ─────────────│
   │                                                   │
   │  2. service->queryInfo("version")               │
   │        │                                          │
   │        ▼                                          │
   │  3. BpInterface::queryInfo()                    │
   │        │                                          │
   │        ▼                                          │
   │  4. Parcel::writeInterfaceToken()               │
   │  5. Parcel::writeString16("version")            │
   │        │                                          │
   │        ▼                                          │
   │  6. BpBinder::transact(                          │
   │        TRANSACTION_queryInfo, data, reply)       │
   │        │                                          │
   │        ▼                                          │
   │  7. ioctl(/dev/binder, BINDER_WRITE_READ, ...)   │
   │        │                                          │
   │        │            Kernel: binder_call()        │
   │        │                                          │
   │        ▼                                          │
   │  8. Server: onTransact(TRANSACTION_queryInfo, ...)│
   │        │                                          │
   │        ▼                                          │
   │  9. Parcel::readString16() → "version"         │
   │ 10. MyService::queryInfo("version") → 100       │
   │        │                                          │
   │        ▼                                          │
   │ 11. Parcel::writeInt32(100)                     │
   │        │                                          │
   │ 12. ioctl reply ─────────────────────────────►  │
   │                                                   │
   │◄─────────────────────────────────────────────────│
   │                                                   │
   │  13. reply.readInt32() → 100                    │
   │  14. return 100                                  │
   │                                                   │
```

### 4.2 Transaction 码

```cpp
// 系统级 (IBinder 定义)
enum {
    PING_TRANSACTION        = IBinder::PING_TRANSACTION,
    DUMP_TRANSACTION        = IBinder::DUMP_TRANSACTION,
    SHELL_COMMAND_TRANSACTION = IBinder::SHELL_COMMAND_TRANSACTION,
    INTERFACE_TRANSACTION   = IBinder::INTERFACE_TRANSACTION,
    // ...
};

// 应用级 (自定义，从 FIRST_CALL_TRANSACTION 开始)
enum {
    TRANSACTION_queryInfo = IBinder::FIRST_CALL_TRANSACTION,  // 0x00000001
    TRANSACTION_sendData,                                       // 0x00000002
    TRANSACTION_registerCallback,                              // 0x00000003
    // 后续追加...
};
```

---

## 5. 接口定义层

定义服务暴露的接口，**Client 和 Server 必须共享同一份接口定义**。

```cpp
// IService.h
#include <binder/IInterface.h>

class IService : public android::IInterface {
public:
    // 声明接口名 (用于 writeInterfaceToken / checkInterface)
    DECLARE_META_INTERFACE(IService);

    // 纯虚方法: 业务 API
    virtual int queryInfo(const android::String16& key) = 0;
    virtual void sendData(const android::String8& data) = 0;

    // 枚举: Transaction Code
    enum {
        TRANSACTION_queryInfo = android::IBinder::FIRST_CALL_TRANSACTION,
        TRANSACTION_sendData,
    };
};
```

---

## 6. Client 端代理

### 6.1 BpInterface 实现

```cpp
// IServiceClient.h
#include "IService.h"

class IServiceClient : public android::BpInterface<IService> {
public:
    // remote: BpBinder，持有与服务通信的 handle
    IServiceClient(const android::sp<android::IBinder>& remote)
        : android::BpInterface<IService>(remote) {}

    // ===== 业务方法实现 =====

    int queryInfo(const android::String16& key) override {
        android::Parcel data, reply;

        // Step 1: 写入 interface token (安全校验用)
        data.writeInterfaceToken(IService::getInterfaceDescriptor());

        // Step 2: 写入请求参数
        data.writeString16(key);

        // Step 3: 发起 transact，阻塞等待 reply
        android::status_t status = remote()->transact(
            TRANSACTION_queryInfo, data, &reply, 0);

        if (status != android::OK) {
            return -1;
        }

        // Step 4: 解析 reply
        return reply.readInt32();
    }

    void sendData(const android::String8& data) override {
        android::Parcel dataParcel, reply;
        dataParcel.writeInterfaceToken(IService::getInterfaceDescriptor());
        dataParcel.writeString8(data);
        remote()->transact(TRANSACTION_sendData, dataParcel, &reply);
    }
};
```

### 6.2 IMPLEMENT_META_INTERFACE

```cpp
// IService.cpp
#include "IService.h"

// 自动生成 asInterface() 和 getInterfaceDescriptor()
IMPLEMENT_META_INTERFACE(IService, "com.example.IService");
// 展开后:
//  - asInterface(): 从 IBinder 创建 IServiceClient*
//  - getInterfaceDescriptor(): 返回 "com.example.IService"
```

---

## 7. Server 端实现

### 7.1 BnInterface 实现

```cpp
// IServiceServer.h
#include "IService.h"

class IServiceServer : public android::BnInterface<IService> {
public:
    // onTransact: 收到 transact 后分发到具体方法
    android::status_t onTransact(
        uint32_t code,
        const android::Parcel& data,
        android::Parcel* reply,
        uint32_t flags
    ) override {
        // 验证 interface token
        if (data.checkInterfaceToken(this)) {
            return android::BAD_TYPE;
        }

        switch (code) {
            case TRANSACTION_queryInfo: {
                // 读取请求
                android::String16 key = data.readString16();

                // 调用业务逻辑
                int result = queryInfo(key);

                // 写入回复
                reply->writeInt32(result);
                return android::OK;
            }
            case TRANSACTION_sendData: {
                android::String8 dataStr = data.readString8();
                sendData(dataStr);
                return android::OK;
            }
            default:
                // 交给基类处理 (如 PING_TRANSACTION)
                return android::BBinder::onTransact(code, data, reply, flags);
        }
    }

    // ===== 业务方法声明 =====
    int queryInfo(const android::String16& key) override;
    void sendData(const android::String8& data) override;
};
```

### 7.2 业务实现

```cpp
// MyService.cpp
#include "IServiceServer.h"

class MyService : public IServiceServer {
public:
    MyService() : version(100), connectedClients(0) {}

    int queryInfo(const android::String16& key) override {
        if (key == android::String16("version")) {
            return version;
        }
        if (key == android::String16("clients")) {
            return connectedClients;
        }
        return -1;
    }

    void sendData(const android::String8& data) override {
        // 处理接收到的数据
        // ...
    }

private:
    int version;
    int connectedClients;
};
```

---

## 8. ServiceManager

### 8.1 概述

ServiceManager 是**系统服务**，所有服务都向它注册，Client 通过它查找服务。

- 句柄: `0` (已知常量)
- 特殊节点: `/dev/binder` vs `/dev/binderfs` (Android 10+)
- 通信方式: 也是 Binder IPC

### 8.2 服务注册 (Server)

```cpp
#include <binder/IServiceManager.h>

int main() {
    // 1. 创建服务
    android::sp<MyService> service = new MyService();

    // 2. 获取 ServiceManager
    android::sp<android::IServiceManager> sm =
        android::defaultServiceManager();

    // 3. 注册服务 (名称必须全局唯一)
    android::status_t status = sm->addService(
        android::String16("my.custom.service"),
        service->asBinder()  // this
    );

    if (status != android::OK) {
        LOGE("Failed to register service");
        return -1;
    }

    // 4. 进入线程池，等待处理请求
    android::ProcessState::self()->startThreadPool();
    android::IPCThreadState::self()->joinThreadPool();

    return 0;
}
```

### 8.3 服务查找 (Client)

```cpp
#include <binder/IServiceManager.h>

android::sp<IService> getService() {
    android::sp<android::IServiceManager> sm =
        android::defaultServiceManager();

    // 阻塞查询，直到服务可用或超时
    android::sp<android::IBinder> binder =
        sm->getService(android::String16("my.custom.service"));

    // 将 IBinder 转换为具体接口 (asInterface 会创建 BpInterface)
    return android::interface_cast<IService>(binder);
}

void doSomething() {
    android::sp<IService> service = getService();
    if (service != nullptr) {
        int ver = service->queryInfo(android::String16("version"));
    }
}
```

### 8.4 ServiceManager 架构

```
┌────────────────────────────────────────────────────────────┐
│                    ServiceManager                          │
│                  (系统进程, PID=0)                          │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  registry: Map<String, IBinder>                      │   │
│  │  {                                                   │   │
│  │    "window"      → WindowManagerService Binder       │   │
│  │    "activity"   → ActivityManagerService Binder     │   │
│  │    "my.service" → MyService Binder                  │   │
│  │  }                                                   │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  addService(name, binder)  ← 服务注册                       │
│  getService(name)         ← 服务查询                        │
└─────────────────────────────────────────────────────────────┘
```

---

## 9. 线程模型

### 9.1 ProcessState

每个进程**只有一个** `ProcessState` 实例:

```cpp
// ProcessState.cpp (单例)
class ProcessState {
public:
    static sp<ProcessState> self();

    // 打开 /dev/binder 设备
    void startThreadPool();  // 创建线程池

private:
    int mDriverFD;           // /dev/binder 文件描述符
    Vector<sp<Thread>> mThreads;  // 线程池
};

// 使用
ProcessState::self()->startThreadPool();
```

### 9.2 IPCThreadState

每个线程**有一个** `IPCThreadState`:

```cpp
// 线程本地存储
class IPCThreadState {
public:
    static IPCThreadState* self();  // pthread_getspecific

    // 进入主循环: 从 binder 读取命令并执行
    void joinThreadPool();

    // 发起一次 transact
    status_t transact(int32_t handle, uint32_t code,
                      const Parcel& data, Parcel* reply);

    // 处理接收到的命令
    status_t executeCommand(int32_t cmd);

private:
    int mProcessFD;              // /dev/binder fd
    int mHandle;                 // 目标 binder handle
    Vector<command> mCommandStack;
};
```

### 9.3 线程池架构

```
ProcessState (进程)
  │
  ├── mDriverFD = open("/dev/binder")
  │
  └── 线程池
        │
        ├── Thread 1 ── IPCThreadState::joinThreadPool()
        │              │
        │              └── while (true) {
        │                      readWithStatus = talkWithDriver()
        │                      executeCommand(cmd)
        │                  }
        │
        ├── Thread 2 ── ...
        │
        └── Thread N ── ...
```

### 9.4 并发处理

```
Client A ── transact ──┐
                      │
Client B ── transact ──┼──► /dev/binder ──► Server Thread Pool
                      │                          │
Client C ── transact ──┘                    ┌──► onTransact()
                                             │
                                             └──► MyService::doWork()
```

Server 端可以有**多个线程**同时处理请求，通过 Binder Driver 的 `BC_ENTER_LOOPER` / `BC_REGISTER_LOOPER` 协议协调。

---

## 10. 内存管理

### 10.1 强引用 / 弱引用

```cpp
// 强引用: RefBase::decStrong() 计数到 0 时 delete
android::sp<T>   // sp = strong pointer

// 弱引用: RefBase::decWeak() 计数到 0 时仅释放对象，不 delete
//         需先 attemptIncStrong() 转强引用
android::wp<T>   // wp = weak pointer
```

### 10.2 跨进程传递 Binder

```cpp
// Server 端
void sendBinder(const sp<IBinder>& binder) {
    reply->writeStrongBinder(binder);
}

// Client 端
sp<IBinder> binder = reply->readStrongBinder();
sp<IMyService> service = interface_cast<IMyService>(binder);
```

### 10.3 Parcel 中的文件描述符

```cpp
// 发送端
int fd = open("/dev/null", O_RDWR);
data.writeFileDescriptor(fd);

// 接收端
int fd = data.readFileDescriptor();
// 注意: fd 会在 Parcel 析构时自动 close
```

---

## 11. 安全机制

### 11.1 Interface Token

```cpp
// Client 写入
data.writeInterfaceToken(IService::getInterfaceDescriptor());

// Server 读取并校验
bool checkInterfaceToken(const android::sp<IBinder>& binder) {
    const String16& desc = data.readInterfaceToken();
    return desc == getInterfaceDescriptor();
}
```

### 11.2 Permission Check

```cpp
// Server 端检查权限
android::status_t onTransact(...) override {
    // 检查调用者权限
    if (defaultServiceManager()->checkCallingPermission(
            android::String16("android.permission.READ_PHONE_STATE"))
            != android::PERMISSION_GRANTED) {
        return android::PERMISSION_DENIED;
    }
    // ...
}
```

### 11.3 UID/PID 验证

```cpp
// 获取调用者身份
int32_t uid = getCallingUid();
int32_t pid = getCallingPid();
```

---

## 12. 实战模板

### 12.1 文件结构

```
my_service/
├── Android.bp              # Blueprint 构建配置
├── src/
│   ├── IService.h          # 接口定义
│   ├── IService.cpp        # IMPLEMENT_META_INTERFACE
│   ├── IServiceClient.h   # BpInterface
│   ├── IServiceServer.h    # BnInterface
│   ├── MyService.h         # 服务头文件
│   └── MyService.cpp       # 业务实现
└── tests/
    └── MyServiceTest.cpp   # 单元测试
```

### 12.2 Android.bp

```cpp
cc_library_shared {
    name: "libmy_service",
    srcs: [
        "IService.cpp",
        "MyService.cpp",
    ],
    shared_libs: [
        "libbinder",
        "libutils",
        "liblog",
    ],
    cflags: [
        "-Wall",
        "-Werror",
    ],
}

cc_binary {
    name: "my_service",
    srcs: ["main.cpp"],
    shared_libs: ["libmy_service"],
}
```

### 12.3 完整示例

```cpp
// IService.h
#pragma once
#include <binder/IInterface.h>

class IService : public android::IInterface {
public:
    DECLARE_META_INTERFACE(IService);
    virtual int getVersion() = 0;
    virtual void setCallback(const android::String16& cb) = 0;
    enum { TRANSACTION_getVersion = 1, TRANSACTION_setCallback = 2 };
};

// IServiceClient.h
class IServiceClient : public android::BpInterface<IService> {
public:
    IServiceClient(const android::sp<android::IBinder>& r)
        : android::BpInterface<IService>(r) {}
    int getVersion() override {
        android::Parcel p, r;
        p.writeInterfaceToken(getInterfaceDescriptor());
        remote()->transact(TRANSACTION_getVersion, p, &r);
        return r.readInt32();
    }
    void setCallback(const android::String16& cb) override {
        android::Parcel p, r;
        p.writeInterfaceToken(getInterfaceDescriptor());
        p.writeString16(cb);
        remote()->transact(TRANSACTION_setCallback, p, &r);
    }
};

// IServiceServer.h
class IServiceServer : public android::BnInterface<IService> {
public:
    android::status_t onTransact(uint32_t code, const android::Parcel& data,
                                  android::Parcel* reply, uint32_t flags) override {
        if (data.checkInterfaceToken(this)) return android::BAD_TYPE;
        switch (code) {
            case TRANSACTION_getVersion:
                reply->writeInt32(getVersion());
                return android::OK;
            case TRANSACTION_setCallback:
                setCallback(data.readString16());
                return android::OK;
        }
        return android::BBinder::onTransact(code, data, reply, flags);
    }
    int getVersion() override { return 100; }
    void setCallback(const android::String16& cb) override { callback = cb; }
private:
    android::String16 callback;
};

// main.cpp
#include <binder/IServiceManager.h>

int main() {
    android::sp sm = android::defaultServiceManager();
    sm->addService(android::String16("my.service"), new IServiceServer());
    android::ProcessState::self()->startThreadPool();
    android::IPCThreadState::self()->joinThreadPool();
    return 0;
}
```

---

## 附录: 关键命令码

| 命令 | 方向 | 说明 |
|------|------|------|
| `BC_TRANSACTION` | Client → Driver | 发起事务 |
| `BC_REPLY` | Server → Driver | 返回结果 |
| `BC_FREE_BUFFER` | Client/Server → Driver | 释放 buffer |
| `BC_INCREFS` | Client → Driver | 增加弱引用 |
| `BC_ACQUIRE` | Client → Driver | 增加强引用 |
| `BR_TRANSACTION` | Driver → Server | 分发事务 |
| `BR_REPLY` | Driver → Client | 分发回复 |
| `BR_DEAD_BINDER` | Driver → Client | 服务死亡通知 |
