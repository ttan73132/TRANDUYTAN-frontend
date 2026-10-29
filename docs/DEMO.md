# Kịch bản demo Nhóm 8

Kịch bản bản 1.2 dùng API nhóm trên Render. Chuẩn bị tài khoản đã xác minh email, được admin nhóm duyệt/gán chi nhánh/phân ca; vị trí chi nhánh khớp GPS thật. Tài khoản quản lý và người nhận bàn giao phải do chủ tài khoản đăng nhập. Không chiếu mật khẩu, OTP hoặc secret.

1. **Giới thiệu**: TRANDUYTAN, Flutter, giao diện riêng, dùng API nhóm HTTPS cấu hình sẵn; không cần Brevo/backend riêng.
2. **Đăng ký / OTP**: tạo tài khoản bằng email thật, nhập OTP, quan sát màn hình chờ duyệt. Sau khi admin duyệt, bấm kiểm tra trạng thái để vào app.
3. **Phân quyền và CRUD**: admin quản lý nhân viên/chi nhánh/ca, manager quản lý ca trong chi nhánh, employee chỉ chấm ca của mình. Sửa/xóa dữ liệu demo chưa có lịch sử; ca đã khóa chỉ sửa tên.
4. **GPS**: mở ca của mình, cấp quyền vị trí khi dùng app. Thử ngoài vùng hoặc sai số chưa đủ chính xác rồi trở lại điều kiện hợp lệ. Chia sẻ vị trí 15 phút, xem ở tài khoản quản lý, dừng chia sẻ.
5. **Motion**: lấy GPS, lắc nhẹ hai lần hoặc chọn nút thay thế. Kiểm tra giờ vào từ server; không sửa đồng hồ thiết bị để tạo giờ chấm công.
6. **Camera**: trong Cá nhân, đồng ý đăng ký khuôn mặt; chụp bằng camera. Đăng xuất, nhập username và chọn khuôn mặt; vẫn cần OTP để đăng nhập.
7. **Dịch trực tiếp**: mở từ Login/Tổng quan, tải mô hình Việt–Anh và Zipformer tiếng Việt 35 MB (Whisper Tiny 104 MB cho Anh/Trung/Nhật). Bật Camera, hướng vào dòng chữ, xem chữ nhận được/bản dịch bên dưới. Dừng Camera, chọn Giọng nói, bấm Bắt đầu nói và nói từng câu ngắn; đợi nhận dạng/dịch trên CPU. Thử Nhập chữ và chuyển tiếng Trung/Nhật. Tắt mạng sau khi đủ mô hình để chứng minh xử lý ngoại tuyến; lưu bàn giao vẫn cần mạng. Xem docs/OFFLINE_TRANSLATION.md.
8. **Bàn giao song ngữ**: chọn ca của mình/người nhận cùng chi nhánh; nhập nội dung, checklist và mã thiết bị như EQ-12 xuất hiện trong cả bản gốc/bản dịch. Gửi phiếu. Người nhận tự đánh dấu đã hiểu và nhập lại mã để hoàn tất. Sửa từ người gửi yêu cầu xác nhận lại; xem lịch sử phiên bản.
9. **Cập nhật dữ liệu**: mở danh sách bàn giao/ca/bảng công trên máy thứ hai; thay đổi từ tài khoản có quyền, chờ tối đa chu kỳ 15 giây cộng thời gian mạng. Thử mất mạng để thấy cảnh báo dữ liệu cũ. Đây là polling khi màn hình mở, không phải thông báo nền.
10. **Trợ lý đối soát ca**: xem tháng, ca thiếu giờ vào/ra hoặc đi muộn/về sớm; so giờ gốc/giờ hiện hành. Gửi đề nghị điều chỉnh của mình; quản lý khác duyệt/từ chối; xem dấu vết trước/sau. Không gọi bảng này là bảng lương.
11. **Kết thúc**: đăng xuất, kiểm tra phiên bị thu hồi. Chỉ trình bày thao tác đã thực hiện thật; kết quả fixture trong test không phải dữ liệu backend thật.

QR hết hạn và Smart Late cũ không thuộc chế độ API nhóm đã chọn. Không dùng tài khoản giả, OTP cố định, ảnh giả hoặc dữ liệu chấm công bịa để thay cho các bước cần tài khoản được duyệt.
