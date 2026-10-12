# ============================================================
#  Git 用户信息配置 + SSH 密钥生成 + 信任区配置 + 连接测试
#  保存时请选择 “UTF-8 with BOM” 编码，否则中文会乱码
# ============================================================

$userName  = Read-Host "请输入你的 Git 用户名"
$userEmail = Read-Host "请输入你的 Git 邮箱"
$passphrase = Read-Host "请输入 SSH 密钥密码（留空表示无密码，直接回车）"

if ([string]::IsNullOrWhiteSpace($userName) -or [string]::IsNullOrWhiteSpace($userEmail)) {
    Write-Host "用户名或邮箱不能为空，脚本终止。" -ForegroundColor Red
    Read-Host "按回车键退出"
    exit 1
}

# --- 配置 Git 全局用户信息 ---
git config --global user.name  "$userName"
git config --global user.email "$userEmail"

Write-Host "Git 用户信息已配置：" -ForegroundColor Green
Write-Host "  用户名: $userName"
Write-Host "  邮箱: $userEmail"
if ([string]::IsNullOrEmpty($passphrase)) {
    Write-Host "  密钥密码: （无）" -ForegroundColor Gray
} else {
    Write-Host "  密钥密码: （已设置）" -ForegroundColor Gray
}
Write-Host ""

# --- 生成 SSH 密钥 ---
$sshKeyPath = "$env:USERPROFILE\.ssh\id_ed25519"

if (Test-Path "$sshKeyPath.pub") {
    Write-Host "SSH 密钥已存在，跳过生成。" -ForegroundColor Yellow
} else {
    # 确保 .ssh 目录存在
    if (-not (Test-Path "$env:USERPROFILE\.ssh")) {
        New-Item -ItemType Directory -Path "$env:USERPROFILE\.ssh" -Force | Out-Null
    }

    # PowerShell 会把空字符串 "" 当成“没有参数”丢掉，
    # 所以空密码必须传 '""' 给 ssh-keygen，否则会报 option requires an argument -- N
    if ([string]::IsNullOrEmpty($passphrase)) {
        $passArg = '""'
    } else {
        $passArg = $passphrase
    }

    ssh-keygen -t ed25519 -C "$userEmail" -f "$sshKeyPath" -N $passArg

    if ($LASTEXITCODE -eq 0) {
        Write-Host "SSH 密钥已生成。" -ForegroundColor Green
    } else {
        Write-Host "SSH 密钥生成失败，请手动检查。" -ForegroundColor Red
        Read-Host "按回车键退出"
        exit 1
    }
}

# --- 复制公钥到剪贴板 ---
Get-Content "$sshKeyPath.pub" | Set-Clipboard
Write-Host ""
Write-Host "公钥已复制到剪贴板！" -ForegroundColor Green
Write-Host "请将公钥添加到 GitHub/GitLab 等平台：" -ForegroundColor Cyan
Write-Host "  GitHub: Settings -> SSH and GPG keys -> New SSH key"
Write-Host "  GitLab: Settings -> SSH Keys"
Write-Host ""
Write-Host "公钥内容预览：" -ForegroundColor Cyan
Get-Content "$sshKeyPath.pub"
Write-Host ""

# --- 信任区配置 + 连接测试 ---
$testHost = Read-Host "如果你已在目标网站配置了公钥，请输入网站地址（如 github.com）；留空跳过"

if (-not [string]::IsNullOrWhiteSpace($testHost)) {
    $testHost = $testHost.Trim()

    # 去掉可能带上的协议前缀和路径
    $testHost = $testHost -replace '^https?://', '' -replace '/.*$', ''

    $sshDir     = "$env:USERPROFILE\.ssh"
    $knownHosts = "$sshDir\known_hosts"

    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }
    if (-not (Test-Path $knownHosts)) {
        New-Item -ItemType File -Path $knownHosts -Force | Out-Null
    }

    Write-Host ""
    Write-Host "正在获取 $testHost 的 SSH 公钥..." -ForegroundColor Cyan
    $scanOutput = ssh-keyscan -t ed25519,rsa $testHost 2>$null

    if ($scanOutput) {
        # 移除该主机的旧记录，避免冲突后加入新记录
        ssh-keygen -R $testHost -f $knownHosts 2>$null | Out-Null
        $scanOutput | Add-Content -Path $knownHosts
        Write-Host "已将 $testHost 加入信任区。" -ForegroundColor Green
    } else {
        Write-Host "无法获取 $testHost 的 SSH 公钥，请检查网络或域名是否正确。" -ForegroundColor Red
        Write-Host "跳过后续连接测试。" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "按回车键退出..." -ForegroundColor Yellow
        Read-Host
        exit 1
    }

    Write-Host ""
    Write-Host "正在测试到 $testHost 的 SSH 连接..." -ForegroundColor Cyan

    # -o BatchMode=yes：避免卡在密码/确认提示上
    $testResult = ssh -T -o BatchMode=yes "git@$testHost" 2>&1
    $testOutput = ($testResult | Out-String).Trim()

    # GitHub 成功时返回退出码 1，所以不能只看退出码，要看输出文本
    if ($testOutput -match "successfully authenticated|Welcome to GitLab|Hi [^!]+!") {
        Write-Host "测试成功！" -ForegroundColor Green
        Write-Host $testOutput -ForegroundColor Gray
    } else {
        Write-Host "测试失败，输出如下：" -ForegroundColor Red
        Write-Host $testOutput -ForegroundColor Gray
        Write-Host ""
        Write-Host "可能的原因：" -ForegroundColor Yellow

        switch -Regex ($testOutput) {
            "Permission denied" {
                Write-Host "  · 公钥未添加到 $testHost，或使用的密钥与该网站上的不匹配。" -ForegroundColor Yellow
            }
            "Host key verification failed" {
                Write-Host "  · 主机密钥验证失败，known_hosts 可能损坏或不存在。" -ForegroundColor Yellow
            }
            "Could not resolve hostname|Name or service not known" {
                Write-Host "  · 域名无法解析，请检查网站地址是否拼写正确。" -ForegroundColor Yellow
            }
            "Connection timed out|Connection refused|Network is unreachable" {
                Write-Host "  · 无法连接到 $testHost，请检查网络、代理或防火墙设置。" -ForegroundColor Yellow
            }
            default {
                Write-Host "  · 未知错误，请根据上面的输出自行排查。" -ForegroundColor Yellow
            }
        }
    }
}

Write-Host ""
Write-Host "按回车键退出..." -ForegroundColor Yellow
Read-Host