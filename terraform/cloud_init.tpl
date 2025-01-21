#cloud-config
write_files:
  - path: /root/.ssh/authorized_keys
    permissions: "0600"
    content: |
      ${public_key}

runcmd:
  - echo "${public_key}" > /root/.ssh/authorized_keys
  - sed -i 's/^#*PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
  - rm -f /etc/ssh/sshd_config.d/50-cloud-init.conf
  # SSH 데몬 재시작
  - systemctl restart sshd
  # 필수 패키지 설치
  - dnf install -y python3 python3-pip
  - dnf install -y epel-release
  - dnf install -y git
  - dnf install -y ansible
  - git clone https://github.com/hwan515/OpenStack-Provisioning.git /root