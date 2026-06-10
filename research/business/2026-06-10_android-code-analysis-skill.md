---
name: android-code-analysis
description: "Android 业务代码分析与问答 - 架构、生命周期、Jetpack、性能优化等"
tags: [android, kotlin, jetpack, lifecycle, architecture]
triggers:
  - android 分析
  - android 问答
  - android 问题
  - 分析 android
  - activity 生命周期
  - viewmodel 状态
  - jetpack 问题
  - room 数据库
  - hilt 依赖注入
  - retrofit 网络
---

# Android 代码分析 Skill

## 功能概述

本 skill 提供 Android 业务开发相关的技术问答，涵盖：
- 架构组件最佳实践（ViewModel、LiveData、StateFlow、Room、Hilt 等）
- Activity/Fragment 生命周期与状态管理
- 依赖注入方案对比
- 网络层架构（Retrofit + Repository）
- 常见问题诊断与解决

---

## 1. Android 架构知识体系

### 1.1 ViewModel + StateFlow/LiveData

**状态管理选择：**
```
LiveData    → 适合 UI 状态，有生命周期感知（自动在 onStop 后停止推送）
StateFlow   → 适合纯 Kotlin，推荐在新项目中使用
SharedFlow  → 适合事件总线、一次性事件
```

**常见问题：**
- ❌ `viewModelScope.launch` 在 onStop 后仍执行 → 用 `lifecycleScope.launchWhenStarted`
- ❌ StateFlow 在 Fragment 中用 `observe` → 用 `collect` 或 `repeatOnLifecycle`

**正确示例：**
```kotlin
// Fragment 中收集状态
lifecycleScope.launch {
    repeatOnLifecycle(Lifecycle.State.STARTED) {
        viewModel.uiState.collect { state ->
            // update UI
        }
    }
}

// ViewModel 中
private val _uiState = MutableStateFlow(UiState())
val uiState: StateFlow<UiState> = _uiState.asStateFlow()
```

### 1.2 Room 数据库

**DAO 写法：**
```kotlin
@Dao
interface UserDao {
    @Query("SELECT * FROM users WHERE id = :id")
    suspend fun getUserById(id: Long): User?
    
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertUser(user: User)
    
    @Transaction
    suspend fun insertUsersWithTransaction(users: List<User>) {
        // 事务操作
    }
}
```

**常见问题：**
- 主线程查询 → 用 `suspend` + Room 的 `withContext(Dispatchers.IO)`
- Flow 收集时 UI 销毁 → 用 `lifecycleScope.launch` + `repeatOnLifecycle`

### 1.3 Hilt 依赖注入

**模块定义：**
```kotlin
@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {
    @Provides
    @Singleton
    fun provideOkHttpClient(): OkHttpClient = 
        OkHttpClient.Builder().build()
}
```

**注入到 ViewModel：**
```kotlin
@HiltViewModel
class UserViewModel @Inject constructor(
    private val userRepository: UserRepository
) : ViewModel()
```

### 1.4 Retrofit + Repository

**网络层架构：**
```
UI → ViewModel → Repository → RemoteDataSource → Retrofit → API
                 ↓
              LocalDataSource → Room
```

**Repository 示例：**
```kotlin
class UserRepository @Inject constructor(
    private val api: UserApi,
    private val userDao: UserDao
) {
    fun getUsers(): Flow<List<User>> = flow {
        val local = userDao.getUsers()
        emit(local) // 先展示本地缓存
        
        try {
            val remote = api.getUsers()
            userDao.insertUsers(remote)
            emit(remote)
        } catch (e: Exception) {
            if (local.isEmpty()) throw e // 本地也为空时抛异常
        }
    }.flowOn(Dispatchers.IO)
}
```

---

## 2. 生命周期要点

### Activity 生命周期顺序
```
启动: onCreate → onStart → onResume
返回: onPause → onStop → onDestroy
重新进入: onRestart → onStart → onResume
```

### Fragment 生命周期
```
onAttach → onCreate → onCreateView → onViewCreated → onStart → onResume
                                    ↓
onPause → onStop → onDestroyView → onDestroy → onDetach
```

### 常见坑点
| 场景 | 问题 | 解决方案 |
|------|------|----------|
| Handler postDelayed | Activity 已销毁仍在执行 | 用 lifecycle-aware 的 postDelayed |
| 协程启动 | Fragment 已 detach 仍在运行 | 用 `viewLifecycleOwner.lifecycleScope` |
| 注册监听器 | Activity 重建后重复注册 | 在 onCreate 中注册，用 flag 防重复 |
| LiveData 观察 | 配置变更后数据不更新 | 用 `ViewModel` + `LiveData` 组合 |

---

## 3. 代码审查清单

### 内存泄漏检查
- [ ] Handler/Runnable 是否在 onDestroy 中移除
- [ ] Listener/Callback 是否在 onDestroy 中置空
- [ ] 非静态内部类是否持有外部引用
- [ ] 静态 ViewHolder 模式是否正确处理 Context 引用
- [ ]协程 Job 是否在 onCleared 中取消

### 线程安全
- [ ] 主线程无网络/IO 操作
- [ ] SharedPreferences 非主线程读写
- [ ] 单例模式中的可变状态是否线程安全

### 空安全
- [ ] lateinit 是否在访问前已赋值
- [ ] by lazy 属性是否可能未被初始化
- [ ] nullable 类型是否做空检查

---

## 4. 问题诊断格式

当用户描述问题时，使用以下格式分析：

```
📱 场景：[用户描述的问题场景]
🔍 可能原因：
   1. [原因1]
   2. [原因2]
💡 建议方案：
   - [方案1]
   - [方案2]
📝 参考代码：[如需要]
⚠️ 注意事项：[重要提醒]
```

---

## 5. 快速参考

### ViewModel 完整示例
```kotlin
@HiltViewModel
class MainViewModel @Inject constructor(
    private val repository: MainRepository
) : ViewModel() {
    
    private val _uiState = MutableStateFlow(MainUiState())
    val uiState: StateFlow<MainUiState> = _uiState.asStateFlow()
    
    private val _events = MutableSharedFlow<UiEvent>()
    val events: SharedFlow<UiEvent> = _events.asSharedFlow()
    
    fun loadData() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            try {
                val data = repository.getData()
                _uiState.update { it.copy(data = data, isLoading = false) }
            } catch (e: Exception) {
                _uiState.update { it.copy(error = e.message, isLoading = false) }
            }
        }
    }
}
```

### Fragment 收集状态
```kotlin
lifecycleScope.launch {
    viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
        launch { viewModel.uiState.collect { /* update UI */ } }
        launch { viewModel.events.collect { /* handle event */ } }
    }
}
```

---

## 限制说明

- ❌ 不生成完整项目代码
- ❌ 不执行 ADB/Device 操作
- ✅ 提供分析、建议、示例代码片段
- ✅ 基于 Android 官方最佳实践