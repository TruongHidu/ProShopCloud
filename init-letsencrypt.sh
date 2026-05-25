#!/bin/bash

# Kiểm tra nếu chưa thay đổi tên miền
domains=(kiottaypos.site www.kiottaypos.site) # THAY BẰNG TÊN MIỀN CỦA BẠN
rsa_key_size=4096
data_path="./certbot"
email="nguyenvantruong1009204@gmail.com" # THAY BẰNG EMAIL CỦA BẠN
staging=0 # Set bằng 1 nếu bạn đang test thử nghiệm để tránh bị Let's Encrypt block (rate limit)

if [ -d "$data_path" ]; then
  read -p "Chứng chỉ đã tồn tại ở $data_path. Bạn có muốn xóa và tạo lại không? (y/N) " decision
  if [ "$decision" != "Y" ] && [ "$decision" != "y" ]; then
    exit
  fi
fi

if [ ! -e "$data_path/conf/options-ssl-nginx.conf" ] || [ ! -e "$data_path/conf/ssl-dhparams.pem" ]; then
  echo "### Đang tải cấu hình SSL Nginx tối ưu từ Let's Encrypt ..."
  mkdir -p "$data_path/conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "$data_path/conf/options-ssl-nginx.conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "$data_path/conf/ssl-dhparams.pem"
  echo
fi

echo "### Đang tạo chứng chỉ SSL giả (dummy) để Nginx có thể khởi động..."
path="/etc/letsencrypt/live/$domains"
mkdir -p "$data_path/conf/live/$domains"
docker compose run --rm --entrypoint "\
  openssl req -x509 -nodes -newkey rsa:$rsa_key_size -days 1\
    -keyout '$path/privkey.pem' \
    -out '$path/fullchain.pem' \
    -subj '/CN=localhost'" certbot
echo

echo "### Đang khởi động Nginx..."
docker compose up --force-recreate -d frontend
echo

echo "### Đang xóa chứng chỉ giả và yêu cầu chứng chỉ thật..."
docker compose run --rm --entrypoint "\
  rm -Rf /etc/letsencrypt/live/$domains && \
  rm -Rf /etc/letsencrypt/archive/$domains && \
  rm -Rf /etc/letsencrypt/renewal/$domains.conf" certbot
echo

echo "### Đang gọi Let's Encrypt để xin chứng chỉ thật..."
# Nối tên miền thành tham số cho certbot
domain_args=""
for domain in "${domains[@]}"; do
  domain_args="$domain_args -d $domain"
done

# Chọn chế độ email
case "$email" in
  "") email_arg="--register-unsafely-without-email" ;;
  *) email_arg="--email $email" ;;
esac

# Chế độ test
if [ $staging != "0" ]; then staging_arg="--staging"; fi

docker compose run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    $staging_arg \
    $email_arg \
    $domain_args \
    --rsa-key-size $rsa_key_size \
    --agree-tos \
    --force-renewal" certbot
echo

echo "### Tải lại cấu hình Nginx..."
docker compose exec frontend nginx -s reload
