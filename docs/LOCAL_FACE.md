# Quét mặt vào thẳng — 1.3.1+9

1. Đăng nhập mật khẩu + OTP hoặc mở phiên đã xác thực bằng vân tay.
2. Cài đặt > Quét mặt bằng camera > Đăng ký khuôn mặt trên máy. Đọc và xác nhận giới hạn camera 2D.
3. Gói SFace khoảng 39 MB tải một lần, kiểm tra kích thước và SHA-256, lưu trong vùng riêng của ứng dụng. Nhìn thẳng, quay nhẹ theo hướng mũi tên, rồi nhìn thẳng lại.
4. Khóa ứng dụng. Chọn **Quét mặt để đăng nhập**. Khi mặt khớp và phiên còn hiệu lực, vào thẳng, không nhập OTP lại.
5. Có thể dùng vân tay xen kẽ, đăng ký lại mặt, hoặc tắt và xóa mẫu. Đăng xuất thu hồi phiên và xóa cả đăng nhập nhanh. Tài khoản pending vẫn cần admin duyệt để chấm công.

## Xử lý trên thiết bị

ML Kit Face Detection 16.1.7 tìm đúng một mặt, lấy góc đầu và năm điểm mắt/mũi/miệng. OpenCV 4.12.0 dùng SFace để căn chỉnh và tạo vector danh tính 128 chiều. So sánh cosine với ngưỡng 0,50. Đây là ngưỡng kỹ thuật của bản này, chưa phải ngưỡng được hiệu chỉnh trên dữ liệu người dùng thật.

Các bước kiểm tra nhìn thẳng/quay đầu/nhìn thẳng lại dùng cùng danh tính. Ảnh tĩnh không hoàn thành bước quay đầu, nhưng kiểm tra chuyển động **không bảo đảm chống video, ảnh động hoặc giả mạo có chủ đích**. Camera 2D có mức bảo vệ thấp hơn vân tay do hệ điều hành kiểm tra. Không gọi đây là Face ID hoặc sinh trắc học phần cứng.

Ảnh tạm do camera tạo trong cache riêng được xóa sau mỗi lần xử lý; không lưu thư viện ảnh, không gửi ảnh hoặc vector tới API. Chỉ tải mô hình qua HTTPS; đăng nhập vẫn gọi API nhóm để làm mới phiên và kiểm tra tài khoản. Không thể bỏ qua tài khoản bị khóa hoặc phiên hết hạn.

Khi bật lựa chọn camera, vector và phiên mới nhất lưu mã hóa bằng flutter_secure_storage trong namespace riêng. Bảo vệ danh tính do lớp nhận diện của app thực hiện, không được khóa bằng sinh trắc học phần cứng. Khi bật đồng thời vân tay, vault phần cứng dùng làm bước xác thực vân tay, sau đó lấy cùng phiên mới nhất. Token cũ trong vault không được gửi lại máy chủ để tránh thu hồi phiên do phát hiện replay. Khi tắt camera, chuyển phiên mới nhất trở lại vault phần cứng nếu vân tay còn bật.

## Nguồn và giấy phép

- OpenCV 4.12.0: Apache-2.0, https://github.com/opencv/opencv/tree/4.12.0
- SFace: Apache-2.0, OpenCV Zoo revision `48b10fa505aeb51fbd127fc60a5c660040e823b7`, file `face_recognition_sface_2021dec.onnx`, 38.696.353 byte; SHA-256 `0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79`.
- Model: https://github.com/opencv/opencv_zoo/tree/48b10fa505aeb51fbd127fc60a5c660040e823b7/models/face_recognition_sface
- ML Kit: https://developers.google.com/ml-kit/vision/face-detection/android
- `tool/device_face_probe.dart` chỉ kiểm tra bằng ảnh mẫu công khai của SFace và `samples/data/lena.jpg` từ OpenCV 4.12.0, kiểm tra SHA-256 trước khi dùng. Không đăng nhập tài khoản, không đọc ảnh người dùng. Không giao APK chẩn đoán cho người dùng. Kết quả ảnh mẫu không thay thế kiểm tra người thật, ánh sáng, góc mặt hoặc thử chống giả mạo.
