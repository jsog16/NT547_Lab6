# NT547 - LAB 06 - BÁO CÁO (TỰ ĐIỀN)

**MSSV:** 25520523 | **Họ tên:** Đặng Vũ Đức Hiển | **Lớp:** NT547.R11.ANTT
**Session code tự sinh:** SC-DE7266 | **Tên contract:** StakingPool_0523
**Solidity / Slither:** 0.8.24 / 0.11.6 | **Ngày hoàn thành:** 20/11/2026
**URL GitHub repository:** https://github.com/jsog16/NT547_Lab6

## 1. Static scan (2,0 điểm)

- Lệnh raw: `python tools/scan.py --mode raw --tag before`
- Số lượng finding raw từ `evidence/before_raw/summary.json`:
  - High: 2; Medium: 3; Low: 1; Informational: 4; Optimization: 1
- Chạy configured: `python tools/scan.py --mode configured --tag before`
- So sánh raw/configured: Low và Informational của configured bị bỏ qua và về 0, các findings còn lại giống nhau (không biến mất High/Medium khi chỉ đổi config)
- 3 detector **khác tên**: msg-value-loop, uninitialized-state, tx-origin

| ID finding | Detector | Impact | Confidence | Source (file:dòng) | Luồng dữ liệu: đầu vào -> thao tác -> tác hại |
|---|---|---|---|---|---|
| F01 | msg-value-loop | High | Medium | AuditTarget.sol:53,54,55,56,57 | Gửi V eth cùng mảng N địa chỉ -> vòng lặp cộng V eth N lần, contract chỉ nhận V -> số dư vượt ngưỡng lưu trong sổ sách, không có khả năng chi trả |
| F02 | uninitialized-state | High | High | AuditTarget.sol:14,49,50,51 | Biến chưa khởi tạo, mặc định address(0) -> lấy làm đích chuyển tiền -> mất vĩnh viễn |
| F03 | tx-origin | Medium | Medium | AuditTarget.sol:63,64,65,66,67 | Owner bị dụ gọi contract attacker, attacker gọi hàm owner -> kiểm tra quyền 'tx.origin == owner' luôn đúng -> attacker bypass và thực thi hàm owner |

## 2. Triage và sửa lỗi (2,5 điểm)

Đọc toàn bộ AuditTarget.sol: nhận diện **4 mẫu lỗi thật + 2 đoạn cần đánh giá ngữ cảnh**,
kể cả khi Slither không hiển thị đủ 6 cảnh báo. Với mẫu không có detector,
ghi “Manual review / Not reported”, KHÔNG sửa slither.json hoặc tạo finding giả.

| Detector + vị trí | TP / FP / Chưa kết luận | Bằng chứng kiểm soát/khả năng khai thác | Biện pháp (Fix / Accept có lý do) | Sau sửa |
|---|---|---|---|---|
| msg-value-loop (High), multiFund L53-57, báo ở L55 | TP | `stakes[receivers[i]] += msg.value` nằm trong vòng lặp, msg.value không đổi qua các vòng. Hàm external payable, ai cũng gọi được. N địa chỉ thì sổ sách ghi N * msg.value nhưng contract chỉ nhận 1 lần. Mảng rỗng thì ETH vào mà không ghi cho ai. | Fix: `require(n > 0)`, `require(msg.value % n == 0)`, tính `share = msg.value / n` trước vòng lặp rồi cộng share. | Hết (xác nhận after_raw, after_configured) |
| uninitialized-state (High), treasury L14, dùng ở payTreasury L49-51 | TP | treasury không có dòng gán nào nên mặc định address(0). payTreasury gọi `treasury.transfer(balance / 2)` gửi một nửa số dư vào address(0), ETH bị đốt vĩnh viễn. | Fix: gán treasury trong constructor (tham số _treasury, require != address(0)). Thêm keyword immutable cho treasury vì luôn cố định từ đầu | Hết (xác nhận after_raw, after_configured), kèm hết constable-states |
| tx-origin (Medium), handOver L63-67, báo ở L64 | TP | Hàm không có onlyOwner, quyền dựa vào tx.origin == owner. Contract trung gian do kẻ tấn công viết vẫn qua được kiểm tra khi owner bị dụ gọi. | Fix: thêm onlyOwner (dùng msg.sender), bỏ dòng require(tx.origin...). | Hết (xác nhận after_raw, after_configured) |
| unchecked-lowlevel (Medium), drainTo L37-40, báo ở L39 | TP | `to.call{value: address(this).balance}("")` bỏ qua kết quả. Nếu to revert thì giao dịch vẫn thành công, owner tưởng đã rút nhưng tiền vẫn nằm trong contract. Compiler cũng cảnh báo ở L39. | Fix: `(bool ok, ) = to.call{...}(""); require(ok, "drain failed");` | Hết (xác nhận after_raw, after_configured) |
| incorrect-equality (Medium), zeroBalance L59-61, báo ở L60 | FP theo ngữ cảnh | Hàm view, chỉ trả bool, không ghi state, không chuyển ETH, không hàm nào gọi nó và không dùng để chặn quyền. Hậu quả tệ nhất là kết quả trả về lệch. | Accept: `// slither-disable-next-line incorrect-equality` ngay trước L60, kèm comment lý do. | Hết (xác nhận after_raw, after_configured) |
| timestamp (Low), releaseTenth L42-47, báo ở L43 | FP theo ngữ cảnh | Chỉ onlyOwner. So sánh với nextRelease là khoá 1 ngày, validator chỉ lệch được vài giây nên không tạo lợi thế. Không dùng làm ngẫu nhiên. nextRelease được cập nhật trước khi gọi call và có require(ok). | Accept, không cần suppress (Low không làm CI RED). | Vẫn còn trong after_raw |

- Mô tả ít nhất 01 kịch bản khai thác TP: người gọi -> điều kiện -> call/state -> hậu quả: Kẻ tấn công deploy contract B có hàm hấp dẫn và dụ owner gọi B. B gọi `handOver(attacker)` `tx.origin == owner` vẫn đúng dù người gọi trực tiếp là B, nên owner bị sửa thành attacker. Sau đó attacker gọi drainTo hoặc ownerWithdraw rút hết ETH.

- Phân tích 01 finding có severity cao nhưng risk thực tế không tương ứng: incorrect-equality (Medium) ở zeroBalance, hàm này chỉ kiểm tra số dư, không ảnh hưởng quyền hay tiền. Trong ngữ cảnh hiện tại, đây là 1 False Positive, tác động thực tế không tương xứng với mức Impact Medium.

- Dẫn bằng chứng `git diff`, scan before/after và giải thích cảnh báo còn lại:
  + Git diff:
```
diff --git a/AuditTarget.sol b/AuditTarget.sol
index 18ae888..d04f1d6 100644
--- a/AuditTarget.sol
+++ b/AuditTarget.sol
@@ -11,7 +11,7 @@ contract StakingPool_0523 {
     address public owner;
     mapping(address => uint256) public stakes;
     uint256 public nextRelease;
-    address payable internal treasury;
+    address payable internal immutable treasury;

     event Deposited(address indexed who, uint256 amount);

@@ -20,8 +20,10 @@ contract StakingPool_0523 {
         _;
     }

-    constructor() {
+    constructor(address payable _treasury) {
         owner = msg.sender;
+	require(_treasury != address(0), "zero");
+	treasury = _treasury;
     }

     function stake() external payable {
@@ -36,7 +38,8 @@ contract StakingPool_0523 {

     function drainTo(address payable to) external onlyOwner {
         require(to != address(0), "zero");
-        to.call{value: address(this).balance}("");
+        (bool ok, ) = to.call{value: address(this).balance}("");
+	require(ok, "drain failed");
     }

     function releaseTenth() external onlyOwner {
@@ -51,17 +54,21 @@ contract StakingPool_0523 {
     }

     function multiFund(address[] calldata receivers) external payable {
+	uint256 n = receivers.length;
+	require(n > 0, "no receivers");
+	require(msg.value % n == 0, "unbalance funds");
+	uint256 share = msg.value / n;
         for (uint256 i = 0; i < receivers.length; i++) {
-            stakes[receivers[i]] += msg.value;
+            stakes[receivers[i]] += share;
         }
     }

     function zeroBalance() external view returns (bool) {
+	// slither-disable-next-line incorrect-equality
         return address(this).balance == 0;
     }

-    function handOver(address newOwner) external {
-        require(tx.origin == owner, "not owner");
+    function handOver(address newOwner) external onlyOwner {
         require(newOwner != address(0), "zero");
         owner = newOwner;
     }
```

  + Before/after: before_raw có 11 result. Gồm 5 Medium/High, 1 timestamp, 3 low-level-calls, 1 naming-convention và 1 constable-states. after_raw hết Medium/High, còn 1 events-access, 1 timestamp, 3 low-level-calls và 1 naming-convention.
  + Cảnh báo còn lại:
    * events-access (Low): Việc thay đổi owner không tạo event, chỉ đơn thuần ảnh hưởng đến việc theo dõi bên ngoài. Accept.
    * timestamp (Low): Chỉ owner gọi, dùng cho khóa thời gian 1 ngày, không dùng làm nguồn ngẫu nhiên. Accept.
    * low-level-calls (Informational): Dùng call để gửi ETH là cách thông dụng, và cả ba đều kiểm tra kết quả sau khi gọi. Accept.
    * naming-convention (Informational): StakingPool_0523 không theo CapWords. Không ảnh hưởng bảo mật. Accept.

## 3. Kiến trúc / Inheritance (1,5 điểm)

- Lệnh printer đã chạy: `slither contracts/ArchitectureDemo.sol --print inheritance-graph --config-file config/slither.raw.json --fail-none`
    + Slither xuất file .dot nằm ở `contracts/ArchitectureDemo.sol.inheritance-graph.dot` (log trong `evidence/architecture/printer_log.txt`), trong khi script `tools/print_arch.py` kiểm tra ở `evidence/architecture/ArchitectureDemo.sol.dot`. Vì vậy em đã copy file sang `evidence/architecture/` và dùng dot render PNG.
- Ảnh đồ thị kế thừa nằm ở `evidence/architecture/inheritance.png`.
- Access control nằm ở `AccessManaged` (biến `admin`, modifier `onlyAdmin`); logic số dư nằm ở `BalanceLedger` (mapping `balances`, hàm `_credit`, `balanceOf`); contract triển khai/được gọi từ bên ngoài là `StudentAsset` (kế thừa cả hai, có entrypoint `mint`).
- Giải thích: Logic security-critical nằm ở hai contract cha: `AccessManaged` quyết định ai được phép gọi (`admin`, `onlyAdmin`), còn `BalanceLedger` quyết định số dư thay đổi thế nào (`_credit`). Entrypoint duy nhất làm thay đổi state từ bên ngoài là `StudentAsset.mint(address,uint256)`, vì `_credit` là `internal` và `balances` không truy cập trực tiếp được. Vì vậy nên audit theo thứ tự mà lời gọi hàm bên ngoài đi qua, tức bắt đầu từ `mint`: kiểm tra `onlyAdmin` có được áp dụng đúng không, rồi lần theo `_credit` để xem state được cập nhật ra sao.

## 4. Red -> Green CI (2,5 điểm)

| Phase | Commit (full/short SHA) | Run URL | Kết quả | Detector khiến RED / lý do GREEN |
|---|---|---|---|---|
| Baseline vulnerable | 55dd13593a9b8e92287964a6dac84da0f0e31c90 | https://github.com/jsog16/NT547_Lab6/actions/runs/44686804104 | RED | msg-value-loop, uninitialized-state, incorrect-equality, tx-origin, unchecked-lowlevel |
| Patched | | | GREEN | |

- So sánh local `--fail-none` (thu thập findings) với CI `fail-on: medium`: ...
- `exclude_low/informational` thay đổi kết quả hiển thị ra sao: ...

## 5. Mutation RED -> GREEN (1,5 điểm)

- Mutation một dòng: `require(msg.sender == owner, "not owner")` -> `require(tx.origin == owner, "not owner")` trong `modifier onlyOwner`.
- Detector kỳ vọng: `tx-origin` (mức Medium); xác nhận của em từ CI: ...

| Phase | Commit SHA | Run URL | Kết quả |
|---|---|---|---|
| Mutation | | | RED |
| Revert mutation | | | GREEN |

- Giải thích sự thay đổi về nguồn định danh/authorization: ...

## 6. Bằng chứng, tự kiểm

- [ ] `AuditTarget.sol`, `lab_identity.json`
- [ ] `evidence/before_raw/` và `evidence/before_configured/`
- [ ] `evidence/after_raw/` và `evidence/after_configured/`
- [ ] `evidence/architecture/`
- [ ] 04 URL Actions run RED/GREEN/RED/GREEN + 04 commit SHA
- [ ] Link repo và ảnh màn hình có terminal / URL / commit SHA; không cắt mất ngữ cảnh
- [ ] Các finding được triage, không chép lại mô tả detector thay cho suy luận
- [ ] Tuyệt đối không có seed phrase, private key, credentials

**Nhận xét cuối cùng (5–7 câu):** ...
