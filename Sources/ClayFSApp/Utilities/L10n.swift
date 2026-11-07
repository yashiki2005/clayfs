import Foundation
import ClayFSCore

public enum L10n {
    public static var currentLanguage: AppLanguage {
        AppLanguage.detect()
    }

    // MARK: - Sidebar & Drive List

    public static var virtualDrives: String {
        switch currentLanguage {
        case .japanese: return "仮想ドライブ"
        case .simplifiedChinese: return "虚拟驱动器"
        case .traditionalChinese: return "虛擬磁碟"
        case .spanish: return "Unidades virtuales"
        case .french: return "Disques virtuels"
        case .german: return "Virtuelle Laufwerke"
        case .korean: return "가상 드라이브"
        case .english: return "Virtual Drives"
        }
    }

    public static var noDrivesRegistered: String {
        switch currentLanguage {
        case .japanese: return "ドライブ未登録"
        case .simplifiedChinese: return "未注册驱动器"
        case .traditionalChinese: return "未註冊磁碟"
        case .spanish: return "Ninguna unidad registrada"
        case .french: return "Aucun disque enregistré"
        case .german: return "Keine Laufwerke registriert"
        case .korean: return "등록된 드라이브 없음"
        case .english: return "No Drives Registered"
        }
    }

    public static var mounted: String {
        switch currentLanguage {
        case .japanese: return "マウント中"
        case .simplifiedChinese: return "已挂载"
        case .traditionalChinese: return "已掛載"
        case .spanish: return "Montado"
        case .french: return "Monté"
        case .german: return "Aktiviert"
        case .korean: return "마운트됨"
        case .english: return "Mounted"
        }
    }

    public static var unmounted: String {
        switch currentLanguage {
        case .japanese: return "未マウント"
        case .simplifiedChinese: return "未挂载"
        case .traditionalChinese: return "未掛載"
        case .spanish: return "Desmontado"
        case .french: return "Non monté"
        case .german: return "Nicht aktiviert"
        case .korean: return "마운트 해제됨"
        case .english: return "Unmounted"
        }
    }

    public static var stopped: String {
        switch currentLanguage {
        case .japanese: return "停止中"
        case .simplifiedChinese: return "已停止"
        case .traditionalChinese: return "已停止"
        case .spanish: return "Detenido"
        case .french: return "Arrêté"
        case .german: return "Gestoppt"
        case .korean: return "중지됨"
        case .english: return "Stopped"
        }
    }

    public static var openInFinder: String {
        switch currentLanguage {
        case .japanese: return "Finder で開く"
        case .simplifiedChinese: return "在访达中打开"
        case .traditionalChinese: return "在 Finder 中打開"
        case .spanish: return "Abrir en Finder"
        case .french: return "Ouvrir dans le Finder"
        case .german: return "Im Finder öffnen"
        case .korean: return "Finder에서 열기"
        case .english: return "Open in Finder"
        }
    }

    public static var unmount: String {
        switch currentLanguage {
        case .japanese: return "アンマウント"
        case .simplifiedChinese: return "卸载"
        case .traditionalChinese: return "卸載"
        case .spanish: return "Desmontar"
        case .french: return "Démonter"
        case .german: return "Deaktivieren"
        case .korean: return "마운트 해제"
        case .english: return "Unmount"
        }
    }

    public static var mount: String {
        switch currentLanguage {
        case .japanese: return "マウント"
        case .simplifiedChinese: return "挂载"
        case .traditionalChinese: return "掛載"
        case .spanish: return "Montar"
        case .french: return "Monter"
        case .german: return "Aktivieren"
        case .korean: return "마운트"
        case .english: return "Mount"
        }
    }

    public static var eject: String {
        switch currentLanguage {
        case .japanese: return "解除"
        case .simplifiedChinese: return "推出"
        case .traditionalChinese: return "退出"
        case .spanish: return "Expulsar"
        case .french: return "Éjecter"
        case .german: return "Auswerfen"
        case .korean: return "추출"
        case .english: return "Eject"
        }
    }

    public static var removeFromList: String {
        switch currentLanguage {
        case .japanese: return "リストから削除"
        case .simplifiedChinese: return "从列表中移除"
        case .traditionalChinese: return "從列表中移除"
        case .spanish: return "Eliminar de la lista"
        case .french: return "Supprimer de la liste"
        case .german: return "Aus Liste entfernen"
        case .korean: return "목록에서 제거"
        case .english: return "Remove from List"
        }
    }

    public static var newDrive: String {
        switch currentLanguage {
        case .japanese: return "新規ドライブ"
        case .simplifiedChinese: return "新建驱动器"
        case .traditionalChinese: return "新建磁碟"
        case .spanish: return "Nueva unidad"
        case .french: return "Nouveau disque"
        case .german: return "Neues Laufwerk"
        case .korean: return "새 드라이브"
        case .english: return "New Drive"
        }
    }

    // MARK: - Detail View & Storage

    public static var storageUsage: String {
        switch currentLanguage {
        case .japanese: return "ストレージ使用量"
        case .simplifiedChinese: return "存储空间使用情况"
        case .traditionalChinese: return "儲存空間使用情況"
        case .spanish: return "Uso de almacenamiento"
        case .french: return "Utilisation du stockage"
        case .german: return "Speicherbelegung"
        case .korean: return "저장 공간 사용량"
        case .english: return "Storage Usage"
        }
    }

    public static func freeSpace(_ free: String) -> String {
        switch currentLanguage {
        case .japanese: return "空き \(free)"
        case .simplifiedChinese: return "可用 \(free)"
        case .traditionalChinese: return "可用 \(free)"
        case .spanish: return "Libre: \(free)"
        case .french: return "Libre : \(free)"
        case .german: return "Frei: \(free)"
        case .korean: return "여유 \(free)"
        case .english: return "Free \(free)"
        }
    }

    public static func storageSummary(used: String, total: String, free: String) -> String {
        "\(used) / \(total) (\(freeSpace(free)))"
    }

    // MARK: - Snapshot & Timeline

    public static var snapshotMemoPlaceholder: String {
        switch currentLanguage {
        case .japanese: return "スナップショットのメモ..."
        case .simplifiedChinese: return "快照备注..."
        case .traditionalChinese: return "快照備忘錄..."
        case .spanish: return "Nota de instantánea..."
        case .french: return "Mémo d'instantané..."
        case .german: return "Schnappschuss-Notiz..."
        case .korean: return "스냅샷 메모..."
        case .english: return "Snapshot memo..."
        }
    }

    public static var save: String {
        switch currentLanguage {
        case .japanese: return "保存"
        case .simplifiedChinese: return "保存"
        case .traditionalChinese: return "儲存"
        case .spanish: return "Guardar"
        case .french: return "Enregistrer"
        case .german: return "Speichern"
        case .korean: return "저장"
        case .english: return "Save"
        }
    }

    public static var timelineHistory: String {
        switch currentLanguage {
        case .japanese: return "タイムライン (履歴)"
        case .simplifiedChinese: return "时间线 (历史记录)"
        case .traditionalChinese: return "時間線 (歷史記錄)"
        case .spanish: return "Línea de tiempo (Historial)"
        case .french: return "Chronologie (Historique)"
        case .german: return "Zeitachse (Verlauf)"
        case .korean: return "타임라인 (기록)"
        case .english: return "Timeline (History)"
        }
    }

    public static func itemCount(_ count: Int) -> String {
        switch currentLanguage {
        case .japanese: return "\(count) 件"
        case .simplifiedChinese: return "\(count) 条记录"
        case .traditionalChinese: return "\(count) 個項目"
        case .spanish: return count == 1 ? "1 elemento" : "\(count) elementos"
        case .french: return count == 1 ? "1 élément" : "\(count) éléments"
        case .german: return count == 1 ? "1 Eintrag" : "\(count) Einträge"
        case .korean: return "\(count)개 항목"
        case .english: return count == 1 ? "1 item" : "\(count) items"
        }
    }

    public static var emptyTimelineMessage: String {
        switch currentLanguage {
        case .japanese:
            return "履歴はまだありません。保存するかファイルを編集すると自動作成されます。"
        case .simplifiedChinese:
            return "暂无历史快照。手动保存或编辑文件将自动创建快照。"
        case .traditionalChinese:
            return "尚無歷史快照。手動儲存或編輯檔案將自動建立快照。"
        case .spanish:
            return "Aún no hay instantáneas. Guarde o edite archivos para crearlas automáticamente."
        case .french:
            return "Aucun instantané pour le moment. Enregistrez ou modifiez des fichiers pour créer l'historique automatiquement."
        case .german:
            return "Noch keine Schnappschüsse vorhanden. Speichern oder bearbeiten Sie Dateien für automatische Historie."
        case .korean:
            return "아직 스냅샷이 없습니다. 저장하거나 파일을 수정하면 자동으로 기록됩니다."
        case .english:
            return "No snapshots yet. Take a snapshot or edit files to record history automatically."
        }
    }

    public static var restore: String {
        switch currentLanguage {
        case .japanese: return "復元"
        case .simplifiedChinese: return "恢复"
        case .traditionalChinese: return "還原"
        case .spanish: return "Restaurar"
        case .french: return "Restaurer"
        case .german: return "Wiederherstellen"
        case .korean: return "복원"
        case .english: return "Restore"
        }
    }

    // MARK: - Empty States

    public static var unmountedNotice: String {
        switch currentLanguage {
        case .japanese:
            return "このドライブは現在マウントされていません。\n「マウント」を押すと Finder に現れ、作業を開始できます。"
        case .simplifiedChinese:
            return "该驱动器当前未挂载。\n点击“挂载”即可在访达中显示并开始使用。"
        case .traditionalChinese:
            return "此磁碟目前未掛載。\n點擊「掛載」即可在 Finder 中顯示並開始使用。"
        case .spanish:
            return "Esta unidad no está montada actualmente.\nHaga clic en 'Montar' para comenzar a trabajar."
        case .french:
            return "Ce disque n'est pas monté actuellement.\nCliquez sur « Monter » pour l'ouvrir dans le Finder."
        case .german:
            return "Dieses Laufwerk ist derzeit nicht aktiviert.\nKlicken Sie auf „Aktivieren“, um im Finder zu starten."
        case .korean:
            return "이 드라이브는 현재 마운트되어 있지 않습니다.\n'마운트'를 클릭하면 Finder에 표시되어 작업을 시작할 수 있습니다."
        case .english:
            return "This drive is currently unmounted.\nClick 'Mount' to mount it in Finder and start working."
        }
    }

    public static var noDriveSelectedNotice: String {
        switch currentLanguage {
        case .japanese:
            return "左のリストからドライブを選択するか、\n「新規ドライブ」を作成してください。"
        case .simplifiedChinese:
            return "请从左侧列表选择驱动器，\n或点击“新建驱动器”。"
        case .traditionalChinese:
            return "請從左側列表選擇磁碟，\n或點擊「新建磁碟」。"
        case .spanish:
            return "Seleccione una unidad de la barra lateral,\no haga clic en 'Nueva unidad' para crear una."
        case .french:
            return "Sélectionnez un disque dans la barre latérale,\nou cliquez sur « Nouveau disque »."
        case .german:
            return "Wählen Sie ein Laufwerk aus der Seitenleiste,\noder erstellen Sie ein neues."
        case .korean:
            return "사이드바에서 드라이브를 선택하거나\n'새 드라이브'를 생성하십시오."
        case .english:
            return "Select a drive from the sidebar,\nor click 'New Drive' to create one."
        }
    }

    // MARK: - Footer

    public static var quit: String {
        switch currentLanguage {
        case .japanese: return "終了"
        case .simplifiedChinese: return "退出"
        case .traditionalChinese: return "結束"
        case .spanish: return "Salir"
        case .french: return "Quitter"
        case .german: return "Beenden"
        case .korean: return "종료"
        case .english: return "Quit"
        }
    }

    // MARK: - Create Drive Sheet

    public static var createDriveTitle: String {
        switch currentLanguage {
        case .japanese: return "新しい ClayFS 仮想ドライブ"
        case .simplifiedChinese: return "新建 ClayFS 虚拟驱动器"
        case .traditionalChinese: return "新建 ClayFS 虛擬磁碟"
        case .spanish: return "Nueva unidad virtual ClayFS"
        case .french: return "Nouveau disque virtuel ClayFS"
        case .german: return "Neues virtuelles ClayFS-Laufwerk"
        case .korean: return "새로운 ClayFS 가상 드라이브"
        case .english: return "New ClayFS Virtual Drive"
        }
    }

    public static var driveNamePlaceholder: String {
        switch currentLanguage {
        case .japanese: return "ドライブ名 (例: Projects)"
        case .simplifiedChinese: return "驱动器名称 (例如: Projects)"
        case .traditionalChinese: return "磁碟名稱 (例如: Projects)"
        case .spanish: return "Nombre de la unidad (ej. Proyectos)"
        case .french: return "Nom du disque (ex. Projets)"
        case .german: return "Laufwerksname (z. B. Projekte)"
        case .korean: return "드라이브 이름 (예: Projects)"
        case .english: return "Drive Name (e.g. Projects)"
        }
    }

    public static var driveSizePlaceholder: String {
        switch currentLanguage {
        case .japanese: return "上限容量 (例: 50g, 100g)"
        case .simplifiedChinese: return "容量上限 (例如: 50g, 100g)"
        case .traditionalChinese: return "容量上限 (例如: 50g, 100g)"
        case .spanish: return "Capacidad máxima (ej. 50g, 100g)"
        case .french: return "Capacité max (ex. 50g, 100g)"
        case .german: return "Max. Kapazität (z. B. 50g, 100g)"
        case .korean: return "최대 용량 (예: 50g, 100g)"
        case .english: return "Max Capacity (e.g. 50g, 100g)"
        }
    }

    public static var drivePathPlaceholder: String {
        switch currentLanguage {
        case .japanese: return "保存先パス (空欄でホームディレクトリ)"
        case .simplifiedChinese: return "存储路径 (留空默认为主目录)"
        case .traditionalChinese: return "儲存路徑 (留空預設為個人目錄)"
        case .spanish: return "Ruta de guardado (vacío para inicio)"
        case .french: return "Emplacement (vide pour dossier départ)"
        case .german: return "Speicherpfad (leer für Benutzerordner)"
        case .korean: return "저장 경로 (비워두면 홈 디렉토리)"
        case .english: return "Storage Path (leave blank for home dir)"
        }
    }

    public static var cancel: String {
        switch currentLanguage {
        case .japanese: return "キャンセル"
        case .simplifiedChinese: return "取消"
        case .traditionalChinese: return "取消"
        case .spanish: return "Cancelar"
        case .french: return "Annuler"
        case .german: return "Abbrechen"
        case .korean: return "취소"
        case .english: return "Cancel"
        }
    }

    public static var create: String {
        switch currentLanguage {
        case .japanese: return "作成"
        case .simplifiedChinese: return "创建"
        case .traditionalChinese: return "建立"
        case .spanish: return "Crear"
        case .french: return "Créer"
        case .german: return "Erstellen"
        case .korean: return "생성"
        case .english: return "Create"
        }
    }

    public static func createError(_ msg: String) -> String {
        switch currentLanguage {
        case .japanese: return "作成エラー: \(msg)"
        case .simplifiedChinese: return "创建错误: \(msg)"
        case .traditionalChinese: return "建立錯誤: \(msg)"
        case .spanish: return "Error de creación: \(msg)"
        case .french: return "Erreur de création : \(msg)"
        case .german: return "Erstellungsfehler: \(msg)"
        case .korean: return "생성 오류: \(msg)"
        case .english: return "Creation Error: \(msg)"
        }
    }

    // MARK: - Restore Confirmation Sheet

    public static var restoreConfirmTitle: String {
        switch currentLanguage {
        case .japanese: return "スナップショットを復元"
        case .simplifiedChinese: return "恢复快照"
        case .traditionalChinese: return "還原快照"
        case .spanish: return "Restaurar instantánea"
        case .french: return "Restaurer l'instantané"
        case .german: return "Schnappschuss wiederherstellen"
        case .korean: return "스냅샷 복원"
        case .english: return "Restore Snapshot"
        }
    }

    public static var restoreConfirmExplanation: String {
        switch currentLanguage {
        case .japanese:
            return "現在のドライブの内容をこの状態に復元します。\n※復元直前の現在の状態も安全スナップショットとして自動保存されるため、いつでもやり直せます。"
        case .simplifiedChinese:
            return "将驱动器内容恢复到此快照状态。\n* 恢复前将自动保存当前状态为安全快照，随时可以重新还原。"
        case .traditionalChinese:
            return "將磁碟內容還原至此快照狀態。\n* 還原前會自動將目前狀態儲存為安全快照，隨時可再次復原。"
        case .spanish:
            return "Restaura la unidad al estado de esta instantánea.\n* El estado actual se guarda automáticamente como copia de seguridad antes de restaurar."
        case .french:
            return "Restaure le disque à l'état de cet instantané.\n* L'état actuel est automatiquement enregistré comme sauvegarde de sécurité avant la restauration."
        case .german:
            return "Stellt das Laufwerk auf diesen Schnappschuss-Zustand wieder her.\n* Der aktuelle Zustand wird vorab automatisch als Sicherheits-Schnappschuss gesichert."
        case .korean:
            return "드라이브 내용을 이 스냅샷 상태로 복원합니다.\n* 복원 직전의 현재 상태도 안전 스냅샷으로 자동 백업되어 언제든 되돌릴 수 있습니다."
        case .english:
            return "Restores the drive to this snapshot state.\n* Current drive state is automatically saved as a safety snapshot before restoring, so you can always roll back."
        }
    }

    public static var executeRestoreButton: String {
        switch currentLanguage {
        case .japanese: return "復元を実行"
        case .simplifiedChinese: return "执行恢复"
        case .traditionalChinese: return "執行還原"
        case .spanish: return "Ejecutar restauración"
        case .french: return "Exécuter la restauration"
        case .german: return "Wiederherstellung ausführen"
        case .korean: return "복원 실행"
        case .english: return "Execute Restore"
        }
    }

    // MARK: - Save Modal Overlay

    public static var savingSnapshotTitle: String {
        switch currentLanguage {
        case .japanese: return "スナップショットを保存中..."
        case .simplifiedChinese: return "正在保存快照..."
        case .traditionalChinese: return "正在儲存快照..."
        case .spanish: return "Guardando instantánea..."
        case .french: return "Enregistrement de l'instantané..."
        case .german: return "Schnappschuss wird gespeichert..."
        case .korean: return "스냅샷 저장 중..."
        case .english: return "Saving Snapshot..."
        }
    }

    public static var saveSuccessTitle: String {
        switch currentLanguage {
        case .japanese: return "スナップショット保存完了"
        case .simplifiedChinese: return "快照保存完成"
        case .traditionalChinese: return "快照儲存完成"
        case .spanish: return "Instantánea guardada"
        case .french: return "Instantané enregistré"
        case .german: return "Schnappschuss gespeichert"
        case .korean: return "스냅샷 저장 완료"
        case .english: return "Snapshot Saved"
        }
    }

    public static var recordingCowStage: String {
        switch currentLanguage {
        case .japanese: return "APFS CoW で現在の状態を記録中..."
        case .simplifiedChinese: return "正在使用 APFS CoW 记录状态..."
        case .traditionalChinese: return "正在使用 APFS CoW 記錄狀態..."
        case .spanish: return "Registrando estado con APFS CoW..."
        case .french: return "Enregistrement de l'état avec APFS CoW..."
        case .german: return "Zustand wird mit APFS CoW aufgezeichnet..."
        case .korean: return "APFS CoW로 현재 상태 기록 중..."
        case .english: return "Recording workspace state with APFS CoW..."
        }
    }

    public static func saveDoneStage(_ id: String) -> String {
        switch currentLanguage {
        case .japanese: return "保存完了: [\(id)]"
        case .simplifiedChinese: return "保存完成: [\(id)]"
        case .traditionalChinese: return "儲存完成: [\(id)]"
        case .spanish: return "Guardado: [\(id)]"
        case .french: return "Enregistré : [\(id)]"
        case .german: return "Gespeichert: [\(id)]"
        case .korean: return "저장 완료: [\(id)]"
        case .english: return "Saved: [\(id)]"
        }
    }

    public static func saveFailed(_ err: String) -> String {
        switch currentLanguage {
        case .japanese: return "スナップショット失敗: \(err)"
        case .simplifiedChinese: return "快照保存失败: \(err)"
        case .traditionalChinese: return "快照儲存失敗: \(err)"
        case .spanish: return "Error al guardar instantánea: \(err)"
        case .french: return "Échec de l'instantané : \(err)"
        case .german: return "Fehler beim Speichern: \(err)"
        case .korean: return "스냅샷 실패: \(err)"
        case .english: return "Snapshot failed: \(err)"
        }
    }

    // MARK: - Restore Modal Overlay

    public static var restoringTitle: String {
        switch currentLanguage {
        case .japanese: return "過去の状態に復元中 (タイムトラベル)..."
        case .simplifiedChinese: return "正在恢复历史状态 (时光回溯)..."
        case .traditionalChinese: return "正在還原歷史狀態 (時光回溯)..."
        case .spanish: return "Restaurando estado anterior (Viaje en el tiempo)..."
        case .french: return "Restauration de l'état antérieur (Voyage dans le temps)..."
        case .german: return "Zustand wird wiederhergestellt (Zeitreise)..."
        case .korean: return "과거 상태로 복원 중 (타임머신)..."
        case .english: return "Restoring Snapshot (Time Travel)..."
        }
    }

    public static var restoreSuccessTitle: String {
        switch currentLanguage {
        case .japanese: return "復元完了"
        case .simplifiedChinese: return "恢复完成"
        case .traditionalChinese: return "還原完成"
        case .spanish: return "Restauración completada"
        case .french: return "Restauration terminée"
        case .german: return "Wiederherstellung abgeschlossen"
        case .korean: return "복원 완료"
        case .english: return "Restore Completed"
        }
    }

    public static var restoringStage: String {
        switch currentLanguage {
        case .japanese: return "過去のスナップショットを展開中 (タイムトラベル)..."
        case .simplifiedChinese: return "正在解包快照状态 (时光回溯)..."
        case .traditionalChinese: return "正在解包快照狀態 (時光回溯)..."
        case .spanish: return "Desempaquetando estado de instantánea..."
        case .french: return "Déballage de l'instantané en cours..."
        case .german: return "Schnappschuss-Zustand wird entpackt..."
        case .korean: return "과거 스냅샷 전개 중 (타임머신)..."
        case .english: return "Unpacking snapshot state (Time Travel)..."
        }
    }

    public static func restoreDoneStage(_ id: String) -> String {
        switch currentLanguage {
        case .japanese: return "[\(id)] の状態に復元完了！"
        case .simplifiedChinese: return "已成功恢复至 [\(id)]！"
        case .traditionalChinese: return "已成功還原至 [\(id)]！"
        case .spanish: return "¡Restaurado con éxito a [\(id)]!"
        case .french: return "Restauré avec succès sur [\(id)] !"
        case .german: return "Erfolgreich auf [\(id)] wiederhergestellt!"
        case .korean: return "[\(id)] 상태로 복원 완료!"
        case .english: return "Successfully restored to [\(id)]!"
        }
    }

    public static func restoredMessage(_ id: String) -> String {
        switch currentLanguage {
        case .japanese: return "[\(id)] へ復元完了"
        case .simplifiedChinese: return "已恢复至 [\(id)]"
        case .traditionalChinese: return "已還原至 [\(id)]"
        case .spanish: return "Restaurado a [\(id)]"
        case .french: return "Restauré à [\(id)]"
        case .german: return "Auf [\(id)] wiederhergestellt"
        case .korean: return "[\(id)] 복원 완료"
        case .english: return "Restored to [\(id)]"
        }
    }

    public static func restoreFailed(_ err: String) -> String {
        switch currentLanguage {
        case .japanese: return "復元失敗: \(err)"
        case .simplifiedChinese: return "恢复失败: \(err)"
        case .traditionalChinese: return "還原失敗: \(err)"
        case .spanish: return "Error de restauración: \(err)"
        case .french: return "Échec de la restauration : \(err)"
        case .german: return "Wiederherstellung fehlgeschlagen: \(err)"
        case .korean: return "복원 실패: \(err)"
        case .english: return "Restore failed: \(err)"
        }
    }

    // MARK: - Status Messages

    public static var mounting: String {
        switch currentLanguage {
        case .japanese: return "マウント中..."
        case .simplifiedChinese: return "正在挂载..."
        case .traditionalChinese: return "正在掛載..."
        case .spanish: return "Montando..."
        case .french: return "Montage en cours..."
        case .german: return "Wird aktiviert..."
        case .korean: return "마운트 중..."
        case .english: return "Mounting..."
        }
    }

    public static func mountFailed(_ err: String) -> String {
        switch currentLanguage {
        case .japanese: return "マウント失敗: \(err)"
        case .simplifiedChinese: return "挂载失败: \(err)"
        case .traditionalChinese: return "掛載失敗: \(err)"
        case .spanish: return "Error al montar: \(err)"
        case .french: return "Échec du montage : \(err)"
        case .german: return "Aktivierung fehlgeschlagen: \(err)"
        case .korean: return "마운트 실패: \(err)"
        case .english: return "Mount failed: \(err)"
        }
    }

    public static var unmounting: String {
        switch currentLanguage {
        case .japanese: return "アンマウント中..."
        case .simplifiedChinese: return "正在卸载..."
        case .traditionalChinese: return "正在卸載..."
        case .spanish: return "Desmontando..."
        case .french: return "Démontage en cours..."
        case .german: return "Wird deaktiviert..."
        case .korean: return "마운트 해제 중..."
        case .english: return "Unmounting..."
        }
    }

    public static func unmountFailed(_ err: String) -> String {
        switch currentLanguage {
        case .japanese: return "アンマウント失敗: \(err)"
        case .simplifiedChinese: return "卸载失败: \(err)"
        case .traditionalChinese: return "卸載失敗: \(err)"
        case .spanish: return "Error al desmontar: \(err)"
        case .french: return "Échec du démontage : \(err)"
        case .german: return "Deaktivierung fehlgeschlagen: \(err)"
        case .korean: return "마운트 해제 실패: \(err)"
        case .english: return "Unmount failed: \(err)"
        }
    }

    public static func autoSaveMessage(_ count: Int) -> String {
        switch currentLanguage {
        case .japanese: return "自動保存 (\(count)件の変更)"
        case .simplifiedChinese: return "自动保存 (\(count) 项更改)"
        case .traditionalChinese: return "自動儲存 (\(count) 項變更)"
        case .spanish: return "Guardado automático (\(count) cambios)"
        case .french: return "Enregistrement auto (\(count) modifications)"
        case .german: return "Automatische Sicherung (\(count) Änderungen)"
        case .korean: return "자동 저장 (\(count)개 변경사항)"
        case .english: return "Auto-save (\(count) changes)"
        }
    }

    public static var compact: String {
        switch currentLanguage {
        case .japanese: return "容量を回収 (Compact)"
        case .simplifiedChinese: return "压缩容量 (Compact)"
        case .traditionalChinese: return "壓縮容量 (Compact)"
        case .spanish: return "Compactar espacio"
        case .french: return "Compacter l'espace"
        case .german: return "Speicherplatz komprimieren"
        case .korean: return "디스크 공간 회수 (Compact)"
        case .english: return "Compact Storage"
        }
    }

    public static var compacting: String {
        switch currentLanguage {
        case .japanese: return "空き容量を回収中 (Compact)..."
        case .simplifiedChinese: return "正在压缩回收存储空间..."
        case .traditionalChinese: return "正在壓縮回收儲存空間..."
        case .spanish: return "Compactando almacenamiento..."
        case .french: return "Compactage de l'espace en cours..."
        case .german: return "Speicherplatz wird komprimiert..."
        case .korean: return "디스크 공간 회수 중..."
        case .english: return "Compacting storage..."
        }
    }

    public static var compactSuccess: String {
        switch currentLanguage {
        case .japanese: return "容量の回収が完了しました"
        case .simplifiedChinese: return "存储空间回收完成"
        case .traditionalChinese: return "儲存空間回收完成"
        case .spanish: return "Almacenamiento compactado con éxito"
        case .french: return "Espace compacté avec succès"
        case .german: return "Speicherplatz erfolgreich komprimiert"
        case .korean: return "디스크 공간 회수 완료"
        case .english: return "Storage successfully compacted"
        }
    }

    public static func compactFailed(_ err: String) -> String {
        switch currentLanguage {
        case .japanese: return "容量回収エラー: \(err)"
        case .simplifiedChinese: return "压缩失败: \(err)"
        case .traditionalChinese: return "壓縮失敗: \(err)"
        case .spanish: return "Error al compactar: \(err)"
        case .french: return "Échec du compactage : \(err)"
        case .german: return "Komprimierungsfehler: \(err)"
        case .korean: return "공간 회수 실패: \(err)"
        case .english: return "Compact failed: \(err)"
        }
    }
}
