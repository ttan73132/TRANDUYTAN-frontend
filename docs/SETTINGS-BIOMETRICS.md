# Cài đặt và đăng nhập sinh trắc học (1.3.1+9)

## Cách sử dụng

1. Đăng nhập bằng tên đăng nhập, mật khẩu và OTP email như trước.
2. Chọn bật sinh trắc học khi app hỏi, hoặc mở Cá nhân > Cài đặt > Đăng nhập sinh trắc học. Tài khoản đang chờ duyệt cũng mở được Cài đặt từ màn hình chờ.
3. Xác thực bằng sinh trắc học của điện thoại. Android quyết định phương thức hợp lệ; không thể biến camera 2D thành Face ID. Máy chỉ có khuôn mặt không đạt chuẩn Android Class 3 cần dùng vân tay.
4. Dùng Khóa ứng dụng để quay về đăng nhập; lần sau chọn Đăng nhập bằng vân tay / khuôn mặt. App cũng khóa khi mở lại sau khi ở nền từ 30 giây, hoặc khi khởi động lại.
5. Đăng xuất thu hồi phiên trên máy chủ và xóa đăng nhập nhanh. Lần tiếp theo cần mật khẩu và OTP.

Sinh trắc học cần Android 11 trở lên và đã đăng ký trong Cài đặt điện thoại. Mọi sinh trắc học đã đăng ký trên thiết bị đều có thể mở tài khoản đang lưu. Mất mạng, phiên refresh hết hạn (30 ngày theo API nhóm), bị thu hồi hoặc thay đổi sinh trắc học có thể yêu cầu đăng nhập mật khẩu và OTP lại. Sinh trắc học không tự duyệt tài khoản pending hoặc bỏ qua quyền trên máy chủ.

## Giao diện và hồ sơ

- Cỡ chữ từ 85% đến 140%, kết hợp với cỡ chữ hệ thống; có mẫu xem trước và khôi phục mặc định.
- Năm màu nền sáng: mây trắng, xanh biển, xanh lá, cát ấm, hồng nhạt. Thay đổi áp dụng toàn app.
- Hồ sơ: tên hiển thị, điện thoại, phòng ban, chức vụ và giới thiệu. Lưu riêng theo tài khoản và địa chỉ máy chủ, giữ lại sau khi đóng app hoặc cập nhật APK.
- Hồ sơ chỉ lưu trên thiết bị; không đồng bộ API nhóm. Tên hiển thị không đổi tên trong bảng công. Phòng ban và chức vụ trong hồ sơ là thông tin giới thiệu, không đổi vai trò hoặc quyền. Email và tên đăng nhập vẫn do máy chủ quản lý.

## Cơ chế

Lần đầu vẫn xác minh OTP qua API nhóm. Khi chỉ bật sinh trắc học Android, refresh token chuyển sang namespace Android Keystore riêng, khóa bằng sinh trắc học Class 3; bản token thông thường bị xóa. Khởi động app không tự đọc vault hoặc mở dữ liệu được bảo vệ. Xác thực thành công mới lấy token để gọi `/auth/refresh` và lưu token đã xoay. Khóa trong lúc refresh không được phục hồi màn hình đăng nhập thành công ngoài ý muốn. Phản hồi tải hồ sơ cũ không được mở khóa phiên.

Bản 1.3.1 bổ sung lựa chọn riêng **Quét mặt bằng camera**, xử lý nhận diện trên thiết bị. Khi bật camera, mẫu mặt và phiên mới nhất lưu mã hóa trong namespace riêng, bảo vệ bằng kiểm tra mặt của app, không khóa bằng sinh trắc học phần cứng. Vân tay dùng vault làm bước xác thực rồi lấy cùng phiên mới nhất. Camera 2D yếu hơn vân tay và không bảo đảm chống ảnh/video giả. Xem [LOCAL_FACE.md](LOCAL_FACE.md) để đăng ký, đăng nhập và hiểu giới hạn.

Sinh trắc học do Android xử lý. App không đọc mẫu vân tay, không chụp hoặc gửi ảnh cho chức năng này. Chức năng **Khuôn mặt và OTP qua máy chủ** cũ vẫn là luồng riêng, có bước đồng ý gửi ảnh và vẫn cần OTP.

## Kiểm tra

`test/settings_biometrics_test.dart` kiểm tra lưu giao diện, giới hạn cỡ chữ, hồ sơ theo tài khoản/máy chủ, yêu cầu phiên đã xác thực, không dùng token thường để vượt vault, hủy xác thực, xoay/thu hồi token, khóa trong lúc refresh, tải hồ sơ chậm, đăng xuất, đổi tài khoản và màn hình 320px ở cỡ chữ 140%.

Đối thoại sinh trắc học và chất lượng cảm biến cần xác nhận trực tiếp trên điện thoại. Kiểm thử mock không chứng minh người dùng đã đặt ngón tay hoặc quét mặt thành công.
