# API nhóm đang dùng trong TRANDUYTAN 1.2

Base URL: `https://nguyen-hoai-nam-2380601398-api.onrender.com/v1`.

Source backend tương ứng: https://github.com/ttan73132/TRANDUYTAN-backend. Hợp đồng API nhóm nằm trong tài liệu này; không gửi route QR/giải trình hoặc trường snake_case của giao diện cũ.

Backend của nhóm: https://github.com/wom-sama/nguyen-hoai-nam-2380601398-api. App này dùng giao diện Flutter TRANDUYTAN riêng. Không sửa cấu hình, database hoặc deploy đè backend nhóm.

## Bắt đầu

1. Cài `output/TRANDUYTAN.apk` trên Android 7 trở lên, mở app và chọn **Đăng ký**.
2. Điền họ tên, tên đăng nhập, email nhận được thư và mật khẩu 10–128 ký tự. Tên đăng nhập 3–32 chữ thường/số/dấu `_` hoặc `.`, bắt đầu bằng chữ/số.
3. Nhập OTP từ email. OTP 10 phút, tối đa 5 lần thử, chờ tối thiểu 60 giây giữa các lần gửi lại; giới hạn thực tế do server quyết định.
4. Tài khoản mới ở trạng thái chờ duyệt. Nhờ quản trị viên nhóm kích hoạt và gán chi nhánh; bấm **Kiểm tra trạng thái**. Nhờ admin/manager phân ca đúng giờ và chi nhánh tại vị trí GPS thật.
5. Mở **Ca làm**, chọn ca của mình, lấy GPS và xác nhận. Không thay thời gian điện thoại để tạo dữ liệu chấm công; server dùng đồng hồ riêng.

Render Free có thể cần khởi động khi không dùng. Timeout 75 giây; có nút thử lại. Không tự gửi lại POST khi chưa rõ server đã ghi nhận hay chưa. Màn hình chấm công yêu cầu đọc lại bản ghi sau lỗi mạng không rõ kết quả.

## Nhóm endpoint

| Chức năng | Endpoint chính | Ghi chú |
|---|---|---|
| Xác thực | `/auth/register`, `/auth/login`, `/auth/verify-otp`, `/auth/resend-otp`, `/auth/refresh`, `/auth/logout`, `/me` | `code` khi verify; lưu cả accessToken/refreshToken; refresh xoay token |
| Nhân viên | `/employees` | Chỉ admin ghi; manager đọc phạm vi chi nhánh; employee đọc bản thân |
| Chi nhánh | `/branches` | Chỉ admin ghi; tọa độ và bán kính hợp lệ |
| Ca | `/shifts` | Admin/manager ghi theo phạm vi; ca khóa kế hoạch chỉ sửa title |
| Chấm công | `/attendance`, `/attendance/check-in`, `/attendance/check-out` | POST chỉ shiftId, latitude, longitude, accuracyMeters |
| Điều chỉnh | `/corrections` | Tự gửi/sửa/rút đơn đang chờ; người có quyền khác xét duyệt |
| Vị trí | `/location-shares` | Chia sẻ có hạn; chỉ chủ vị trí được dừng |
| Khuôn mặt | `/face/status`, `/face/enroll`, `/auth/face-login` | Chụp camera, JPEG/PNG tối đa 2 MiB, base64; không bỏ OTP |
| Bàn giao | `/handover-recipients`, `/handovers`, `/handovers/:id/revisions` | PATCH bắt buộc version; chỉ người nhận xác nhận |
| Báo cáo | `/dashboard`, `/reports/monthly?month=YYYY-MM` | Múi giờ server, dữ liệu theo quyền |

Response `{data: ...}`; lỗi `{error:{code,message,details?}}`. CRUD sử dụng PATCH, không gửi trường chỉ đọc. ID người dùng chính là employeeId. Danh sách trả mảng trực tiếp. URL chỉ thêm `/v1` một lần.

## Dịch và bàn giao

Màn hình **Dịch trực tiếp** dùng trước đăng nhập và khi chờ duyệt. Chọn Việt/Anh/Trung/Nhật (`日本語`), tải mô hình, dùng Camera, Giọng nói hoặc Nhập chữ. Camera đọc chữ bằng ML Kit; Zipformer chuyên tiếng Việt và Whisper Tiny cho Anh/Trung/Nhật nhận giọng nói ngoại tuyến theo đoạn, không gửi ảnh/âm thanh lên API. Xem [hướng dẫn chi tiết](OFFLINE_TRANSLATION.md). Phiếu bàn giao vẫn chỉ dùng vi/en/zh theo hợp đồng backend nhóm.

Mô hình tải từ Google; nội dung được dịch trên điện thoại. Chỉ khi chủ động lưu/gửi phiếu bàn giao, bản gốc và bản dịch mới được gửi tới backend nhóm. Có thể sửa bản dịch thủ công.

Trong phiếu bàn giao, chọn ca của chính mình và người nhận đang hoạt động, xác minh email, cùng chi nhánh. Nhập nội dung và checklist. Khi gửi, cần 1–3 thông tin quan trọng có cùng giá trị trong cả nội dung gốc và bản dịch. Hỗ trợ mã thiết bị, số lượng và thời hạn. Số lượng dùng dấu chấm thập phân, không dấu phân cách hàng nghìn; thời hạn dạng `HH:mm` hoặc `YYYY-MM-DD HH:mm`. Xem giá trị chuẩn trước khi gửi.

Người nhận chọn đã hiểu/cần làm rõ. Chỉ người nhận được xác nhận cuối, phải nhập lại đủ dữ kiện; admin không có nút xác nhận hộ. Nếu version đã đổi, tải lại và nhập lại câu trả lời. Author sửa phiếu đã gửi sẽ yêu cầu xác nhận lại; lịch sử cũ được giữ. Không mô tả đối chiếu dữ kiện là chứng nhận bản dịch đúng ngữ nghĩa.

## Cập nhật dữ liệu

Các danh sách đang mở tải lại mỗi 15 giây, chỉ một request mỗi màn hình tại một thời điểm. Màn hình bị che bởi trang khác hoặc app chạy nền tạm dừng polling. Quay lại từ nền sẽ tải mới. Có thời gian cập nhật và nút tải thủ công; mất kết nối giữ bản gần nhất kèm cảnh báo. Không có WebSocket hoặc thông báo đẩy nền trong bản này.

## Build

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release
```

URL nhóm là mặc định. Có thể build với `--dart-define=API_BASE_URL=https://.../v1`; không đưa secret vào dart-define. Khóa ký và `.env` không nằm trong Git/ZIP source. Đăng xuất trước khi đổi máy chủ trong cài đặt app.
