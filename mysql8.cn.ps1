
# # 获取用户输入路径
Write-Host "请输入安装路径并按回车以确认，不输入内容直接回车则使用当前路径"
$userInputPath = Read-Host "安装路径"
$path = if ([string]::IsNullOrWhiteSpace($userInputPath)) {
    Get-Location
} else {
    $userInputPath
}
$path = $path.Path.Replace('\', '\\')
Write-Host "安装路径为: $path"
Write-Host "正在初始化MySQL，请稍等..."
Write-Host "处理配置信息..."
try{
# # 替换my.ini中的路径配置（支持跨盘符路径）
$content = Get-Content "$path\my.ini" -Raw
# 匹配单个文件中的路径
$content = $content -replace '[A-Za-z]:\\+mysql8', "$path"
Set-Content "$path\my.ini" -Value $content -Force -Encoding Default
}catch{
    Write-Error "设置配置信息失败：$($_.Exception.Message)"
    exit 1
}

# # 初始化数据库并捕获临时密码
$log = & "$path\bin\mysqld.exe" --initialize --console 2>&1 | Out-String -Width 9999
# # 保存初始化日志到文件
$log | Out-File -FilePath "$path\initialize.log"

# # 提取临时密码（兼容MySQL 5.7+版本）
$content = Get-Content "initialize.log" -Raw
$temporary = $log.Substring($log.LastIndexOf(":") + 2)
$temporary | Set-Clipboard
Write-Host ('初始化完成，临时密码为：{0}' -f ($temporary))
Write-Host "正在安装服务，请稍等..."
# # 安装MySQL服务（兼容Windows系统）
try{
    & "$path\bin\mysqld.exe" --install MySQL | Tee-Object -FilePath "$path\initialize.log" -Append
    Write-Host "服务安装成功，日志已记录"
}catch{
    Write-Error "服务安装失败：$($_.Exception.Message)"
    exit 1
}
# # 启动MySQL服务并记录日志
try {
    & "net" start "mysql" 2>&1 | Tee-Object -FilePath "$path\initialize.log" -Append
    Write-Host "服务启动成功，日志已记录"
} catch {
    Write-Error "服务启动失败：$($_.Exception.Message)"
    exit 1
}
Write-Host "请在看到输入密码时，点击鼠标右键粘贴密码."
& "$path\bin\mysql.exe" -u root -p
Read-Host -Prompt "按下回车键以退出..."