# Dịch camera và giọng nói trên điện thoại — 1.2.0

Mở **Dịch trực tiếp** từ đăng nhập, chờ duyệt hoặc tổng quan. Không cần tài khoản được admin duyệt để dùng dịch. Hỗ trợ Việt, Anh, Trung, Nhật; chọn đúng ngôn ngữ gốc trong ô **Từ**.

## Camera

1. Chọn cặp ngôn ngữ, tải mô hình dịch lần đầu nếu được yêu cầu.
2. Chọn **Camera**, bấm **Bật camera dịch chữ**, cấp quyền Camera khi dùng app.
3. Hướng camera sau vào chữ, đủ sáng và giữ ổn định. Chữ nhận được và bản dịch nằm bên dưới khung camera; cuộn xuống nếu cần.
4. Bấm **Dừng camera** để giữ kết quả cuối. Rời màn hình hoặc đưa app vào nền cũng dừng camera; quay lại cần bấm bật lại.

Google ML Kit nhận chữ Latin (Việt/Anh), Trung hoặc Nhật theo ngôn ngữ gốc. Mô hình nhận chữ được đóng trong APK. Nhận dạng khoảng mỗi 0,9 giây, chỉ một khung được xử lý tại một thời điểm. App gom vài lần đọc, ưu tiên nội dung lặp lại/đầy đủ hơn, không chờ các khung giống hệt nhau. Nếu chỉ có một khung đọc được rồi các khung sau trống, vẫn đưa nội dung đó sang dịch sau khoảng 1,8 giây. Các bản mới cách tối thiểu 2,5 giây để dễ đọc; nút Dịch ngay chữ vừa đọc bỏ qua thời gian chờ. Khoảng trắng/xuống dòng và chữ hoa/thường không tạo bản dịch trùng; số và dấu câu vẫn được giữ. Khi dịch chữ mới, bản dịch trước vẫn hiện cùng trạng thái cập nhật, không nhấp nháy thành ô trống. Bản dịch nằm bên dưới, chưa gắn lên từng vùng chữ trong ảnh. App không chụp lưu ảnh hoặc tải khung hình lên máy chủ.

## Giọng nói

Từ bản 1.2.0+7, tiếng Việt dùng Zipformer 30M chuyên tiếng Việt, gói khoảng 35 MB. Anh/Trung/Nhật dùng chung gói Whisper Tiny 104 MB đã có. Mỗi gói chỉ tải một lần; đổi ngôn ngữ chỉ kiểm tra và nạp tệp đã lưu. Gói Whisper cũ được giữ khi cập nhật. Chỉ tải lại khi xóa dữ liệu, gỡ app hoặc chuyển phiên bản mô hình. Lúc kiểm tra, màn hình hiện **Đang kiểm tra gói đã tải…** rồi chuyển sang **Bắt đầu nói** nếu gói còn đủ.

1. Chọn **Giọng nói**, chọn đúng ngôn ngữ gốc rồi tải gói hiển thị (35 MB cho tiếng Việt, 104 MB cho Anh/Trung/Nhật), xác nhận tải qua mạng.
2. Tải cặp mô hình dịch nếu chưa có, chọn đúng ngôn ngữ nói, bấm **Bắt đầu nói** và cấp quyền Micro khi dùng app.
3. Nói từng câu rõ ràng. App giữ thêm 0,2 giây đầu có âm lượng thấp để tránh mất đầu từ; cập nhật tạm mỗi khoảng 3 giây, chốt câu sau khoảng 1 giây im lặng hoặc tối đa 10 giây âm thanh. Cộng thêm thời gian xử lý của máy; không phải nhận dạng tức thì từng âm tiết.
4. Bấm **Dừng micro**; app xử lý nốt câu cuối. Khi rời màn hình, đổi cặp ngôn ngữ hoặc app vào nền, app ngừng thu và bỏ kết quả đang chờ.

Âm thanh PCM 16 kHz mono ở bộ nhớ, không lưu tệp và không gửi lên API. Suy luận chạy trong isolate riêng bằng sherpa-onnx/ONNX Runtime trên CPU, không dùng dịch vụ nhận dạng giọng nói qua mạng. Hàng đợi giới hạn để tránh tích lũy âm thanh nếu máy chậm. Môi trường ồn, giọng nhỏ, tên riêng hoặc câu dài có thể làm nhận dạng sai; nói lại hoặc dùng **Nhập chữ** để sửa.

## Ngoại tuyến

Lần đầu cần mạng để tải mô hình dịch Google ML Kit (khoảng 30 MB/ngôn ngữ), Zipformer tiếng Việt (34.188.908 byte) hoặc Whisper Tiny (103.609.903 byte). Sau đó thử khi tắt Wi-Fi/dữ liệu di động: Camera, Giọng nói, Nhập chữ vẫn xử lý trên máy. Đăng nhập, chấm công và lưu bàn giao vẫn cần API nhóm. Chỉ chủ động lưu/gửi phiếu bàn giao mới gửi nội dung phiếu tới backend.

Không có API key dịch hoặc dịch vụ Brevo/Render riêng cho phần dịch. Quyền Camera và Micro chỉ dùng sau khi bấm bắt đầu, không chạy trong nền.

## Mô hình và kiểm tra

- Whisper Tiny đa ngôn ngữ của OpenAI, bản ONNX int8 do dự án sherpa-onnx chuyển đổi. Model upstream: https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny, revision `65176e2deb88badc814a94058666cadccc29b61c`.
- Zipformer tiếng Việt: https://huggingface.co/csukuangfj2/sherpa-onnx-zipformer-vi-30M-int8-2026-02-09, revision `83e140db6d23fbb8480fd5fb868f74ab80e7092c`; nguồn mô hình của hynt: https://huggingface.co/hynt/Zipformer-30M-RNNT-6000h, giấy phép CC BY-NC-ND 4.0 (https://creativecommons.org/licenses/by-nc-nd/4.0/), dùng trong bài tập phi thương mại. Gồm encoder int8, decoder, joiner int8, tokens và bpe.model; nhận dạng bằng modified beam search, 4 đường ứng viên. Không sửa mô hình hoặc phân phối trọng số trong source ZIP.
- Tệp `tiny-encoder.int8.onnx`, `tiny-decoder.int8.onnx`, `tiny-tokens.txt`. App kiểm tra kích thước và SHA-256 trước khi dùng; tải vào tệp `.part`, kiểm tra xong mới đổi tên. Mã hash cố định ở `lib/services/offline_speech.dart`.
- Các tệp mô hình không nằm trong Git/source ZIP. Tải từ nguồn gốc qua HTTPS khi dùng app; có thể tải trước và chép vào thư mục riêng của app để demo. Không đưa âm thanh người dùng vào source.
- Mã thư viện sherpa-onnx và Whisper dùng giấy phép Apache-2.0/MIT tương ứng; xem nguồn https://github.com/k2-fsa/sherpa-onnx và https://github.com/openai/whisper. ML Kit theo điều khoản Google, xem https://developers.google.com/ml-kit/terms.
- `flutter test` kiểm tra định dạng NV21/YUV, độ xoay camera, chọn mô hình chữ, chia đoạn PCM, ngưỡng im lặng và giới hạn độ dài. Kiểm thử fixture không thay thế thử camera/micro thật.
- Công cụ `tool/verify_whisper.dart` nhận WAV và thư mục mô hình để kiểm tra suy luận CPU thật, không gọi API nhận dạng.

Kiểm tra native trên Android bằng entry point dành riêng cho test (không phải app bàn giao): từ root project, chạy `flutter run --release --target tool/device_translation_probe.dart`. Công cụ cần Wi-Fi để tải mô hình/âm thanh mẫu cố định nếu chưa có, tạo ảnh chữ mẫu trong bộ nhớ, chạy OCR Anh/Trung/Nhật và nhận dạng WAV trên CPU, in `TRANSLATION_PROBE PASS` khi đạt. Không dùng tài khoản, camera hoặc micro thật. Sau kiểm tra phải cài lại app chính bằng `flutter run --release --target lib/main.dart`; không giao APK của entry point test. Mô hình nằm trong vùng lưu trữ riêng của app, được giữ khi cài cập nhật.

Phiếu bàn giao trên API nhóm vẫn chỉ lưu `vi/en/zh`; Nhật dùng trong màn hình dịch độc lập.
