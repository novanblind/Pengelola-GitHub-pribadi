require "import"
import "android.app.*"
import "android.content.*"
import "android.widget.*"
import "android.view.*"
import "android.os.*"
import "android.net.Uri"
import "android.util.Base64"
import "android.widget.ScrollView"
import "java.io.*"
import "java.net.URL"
import "java.net.HttpURLConnection"
import "java.lang.Thread"
import "java.lang.Runnable"
import "java.util.zip.ZipInputStream"
import "java.util.zip.ZipEntry"
import "org.json.JSONObject"
import "org.json.JSONArray"

local mainHandler = Handler(Looper.getMainLooper())

-- ==========================================================
-- PENGATURAN VERSI & TAUTAN SKRIP PEMBARUAN
-- ==========================================================
local VERSI_SAAT_INI = "1.13"
local URL_RAW_SCRIPT = "https://raw.githubusercontent.com/novanblind/Pengelola-GitHub-pribadi/main/github.lua"

-- Jalur berkas skrip saat ini untuk pembaruan otomatis
local infoScript = debug.getinfo(1, "S")
local JALUR_BERKAS_SCRIPT = (infoScript and infoScript.source and infoScript.source:sub(1, 1) == "@")
    and infoScript.source:sub(2) or ""

-- Pengaturan nama SharedPreferences dan kunci unik
local PREF_NAME = "github_acc_manager_exclusive_unique_cfg"
local KEY_TOKEN = "key_github_user_pat_unique"
local prefs = service.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)

-- Deklarasi fungsi navigasi bertingkat
local menuUtama, tampilkanDialogLogin
local buatRepoDialog, tambahFileRepoDialog, unggahDariMemoriHPDialog, konfirmUnggahBerkasDialog
local daftarRepoSayaDialog, cariRepoDialog, kelolaRepoPilihanDialog, ubahPrivasiRepoDialog
local bukaDirektoriRepoDialog, menuAksiFile, formEditIsiBerkas, gantiNamaRepoDialog, gantiNamaBerkasDialog, hapusRepoDialog
local cekPembaruan, prosesDownloadPembaruan, aktifkanGitHubPagesOtomatis
local filterRepoDialog, multiSelectRepoDialog
local jalankanOperasiBanyakRepo, prosesHapusBanyakRepo, prosesUbahPrivasiBanyakRepo, tampilkanHasilOperasiBanyak

-- Tautan otomatis pembuatan token dengan izin repo dan delete_repo
local URL_GENERATE_TOKEN = "https://github.com/settings/tokens/new?description=Aksesibilitas+Android&scopes=repo,delete_repo,workflow"
-- Tautan halaman pendaftaran akun GitHub baru
local URL_DAFTAR_AKUN = "https://github.com/signup"

-- ==========================================================
-- FUNGSI UTILITAS UMUM
-- ==========================================================

-- Mengambil tanggal/waktu perubahan terakhir dari repositori
local function ambilWaktuTerakhirEdit(repoObj)
    local pushed = repoObj.optString("pushed_at", "")
    local updated = repoObj.optString("updated_at", "")
    return (pushed > updated) and pushed or updated
end

-- Format ukuran berkas
local function formatUkuranBerkas(bytes)
    if bytes < 1024 then
        return bytes .. " B"
    elseif bytes < 1024 * 1024 then
        return string.format("%.1f KB", bytes / 1024)
    else
        return string.format("%.1f MB", bytes / (1024 * 1024))
    end
end

-- Membaca berkas lokal ke Base64
local function bacaBerkasKeBase64(fileObj)
    local fis = FileInputStream(fileObj)
    local bos = ByteArrayOutputStream()
    local buf = String(string.rep(" ", 4096)).getBytes()
    local n = fis.read(buf)
    while n ~= -1 do
        bos.write(buf, 0, n)
        n = fis.read(buf)
    end
    fis.close()
    return Base64.encodeToString(bos.toByteArray(), Base64.NO_WRAP)
end

-- Menonaktifkan teks kapital bawaan Android (memaksa huruf kecil murni) pada tombol dialog
local function aturTombolHurufKecil(diag, teksPositif, teksNegatif, teksNetral)
    pcall(function()
        if teksPositif then
            local btnPos = diag.getButton(DialogInterface.BUTTON_POSITIVE)
            if btnPos then
                btnPos.setTextAllCaps(false)
                btnPos.setTransformationMethod(nil)
                btnPos.setText(teksPositif)
            end
        end
        if teksNegatif then
            local btnNeg = diag.getButton(DialogInterface.BUTTON_NEGATIVE)
            if btnNeg then
                btnNeg.setTextAllCaps(false)
                btnNeg.setTransformationMethod(nil)
                btnNeg.setText(teksNegatif)
            end
        end
        if teksNetral then
            local btnNeu = diag.getButton(DialogInterface.BUTTON_NEUTRAL)
            if btnNeu then
                btnNeu.setTextAllCaps(false)
                btnNeu.setTransformationMethod(nil)
                btnNeu.setText(teksNetral)
            end
        end
    end)
end

-- Membandingkan dua string versi (mis. "1.4" vs "1.10")
local function bandingkanVersi(vBaru, vLama)
    local tBaru = {}
    for n in tostring(vBaru):gmatch("%d+") do table.insert(tBaru, tonumber(n)) end
    local tLama = {}
    for n in tostring(vLama):gmatch("%d+") do table.insert(tLama, tonumber(n)) end
    for i = 1, math.max(#tBaru, #tLama) do
        local nb = tBaru[i] or 0
        local nl = tLama[i] or 0
        if nb > nl then return true end
        if nb < nl then return false end
    end
    return false
end

-- Menyimpan kode pembaruan ke jalur skrip saat ini
local function simpanFilePembaruan(konten)
    local targetPath = JALUR_BERKAS_SCRIPT
    if targetPath == "" or not File(targetPath).canWrite() then
        if activity and activity.getLuaPath then
            targetPath = tostring(activity.getLuaPath())
        end
    end
    if targetPath ~= "" then
        local file = File(targetPath)
        local parent = file.getParentFile()
        if parent and not parent.exists() then parent.mkdirs() end
        local fos = FileOutputStream(file)
        fos.write(String(konten).getBytes("UTF-8"))
        fos.flush()
        fos.close()
        return true
    end
    return false
end

-- Membuka URL ke browser
local function bukaBrowser(urlTarget)
    local ok, err = pcall(function()
        local intent = Intent(Intent.ACTION_VIEW, Uri.parse(urlTarget))
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        service.startActivity(intent)
    end)
    if not ok then
        Toast.makeText(service, "Gagal buka browser: " .. tostring(err), Toast.LENGTH_SHORT).show()
    end
end

-- Menyalin teks ke clipboard
local function salinKeClipboard(label, teks)
    local clipboard = service.getSystemService(Context.CLIPBOARD_SERVICE)
    local clip = ClipData.newPlainText(label, teks)
    clipboard.setPrimaryClip(clip)
    if service.speak then service.speak(label .. " disalin.") end
    Toast.makeText(service, label .. " disalin!", Toast.LENGTH_SHORT).show()
end

-- Membagikan tautan lewat Share Android
local function bagikanTautan(judul, teks)
    local ok, err = pcall(function()
        local intent = Intent(Intent.ACTION_SEND)
        intent.setType("text/plain")
        intent.putExtra(Intent.EXTRA_SUBJECT, judul)
        intent.putExtra(Intent.EXTRA_TEXT, teks)
        local chooser = Intent.createChooser(intent, "Bagikan via")
        chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        service.startActivity(chooser)
    end)
    if not ok then
        Toast.makeText(service, "Gagal membagikan: " .. tostring(err), Toast.LENGTH_SHORT).show()
    end
end

-- ==========================================================
-- PERMINTAAN HTTP KE GITHUB API (dengan retry otomatis saat gagal jaringan)
-- ==========================================================
local MAX_PERCOBAAN_JARINGAN = 3
local JEDA_DASAR_RETRY_MS = 1200

local function apakahErrorJaringan(pesanError)
    local p = tostring(pesanError)
    if p:find("Gagal%. Kode:") then
        return false
    end
    return true
end

local function kirimPermintaanGitHub(metode, endpoint, token, jsonBody, onSelesai, diam)
    local progress
    if not diam then
        progress = ProgressDialog(service)
        progress.setTitle("Menghubungkan")
        progress.setMessage("Sedang memproses...")
        progress.setCancelable(true)
        progress.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
        progress.show()
    end

    local function jalankanPercobaan(percobaanKe)
        if progress and percobaanKe > 1 then
            pcall(function()
                progress.setMessage("Koneksi gagal, mencoba lagi (" .. percobaanKe .. "/" .. MAX_PERCOBAAN_JARINGAN .. ")...")
            end)
        end

        Thread(Runnable{
            run = function()
                local ok, res = pcall(function()
                    local url = URL(endpoint)
                    local conn = url.openConnection()

                    if metode == "PATCH" then
                        local okPatch = pcall(function() conn.setRequestMethod("PATCH") end)
                        if not okPatch then
                            conn.setRequestMethod("POST")
                            conn.setRequestProperty("X-HTTP-Method-Override", "PATCH")
                        end
                    else
                        conn.setRequestMethod(metode)
                    end

                    conn.setRequestProperty("Authorization", "Bearer " .. token)
                    conn.setRequestProperty("User-Agent", "Android-Accessibility-Manager")
                    conn.setRequestProperty("Accept", "application/vnd.github.v3+json")
                    conn.setRequestProperty("Content-Type", "application/json")
                    conn.setConnectTimeout(15000)
                    conn.setReadTimeout(20000)

                    if jsonBody ~= nil and jsonBody ~= "" then
                        conn.setDoOutput(true)
                        local os = conn.getOutputStream()
                        os.write(String(jsonBody).getBytes("UTF-8"))
                        os.flush()
                        os.close()
                    end

                    local respCode = conn.getResponseCode()
                    local inputStream
                    if respCode >= 200 and respCode < 300 then
                        pcall(function() inputStream = conn.getInputStream() end)
                    else
                        pcall(function() inputStream = conn.getErrorStream() end)
                    end

                    local lines = {}
                    if inputStream ~= nil then
                        local reader = BufferedReader(InputStreamReader(inputStream, "UTF-8"))
                        local line = reader.readLine()
                        while line ~= nil do
                            table.insert(lines, tostring(line))
                            line = reader.readLine()
                        end
                        reader.close()
                    end

                    local hasil = table.concat(lines, "\n")
                    if respCode >= 200 and respCode < 300 then
                        return hasil
                    else
                        local pesanError = "Gagal. Kode: " .. respCode
                        pcall(function()
                            local jsonErr = JSONObject(hasil)
                            pesanError = pesanError .. " (" .. jsonErr.optString("message", "") .. ")"
                        end)
                        error(pesanError)
                    end
                end)

                if ok then
                    mainHandler.post(Runnable{
                        run = function()
                            if progress then
                                pcall(function() progress.dismiss() end)
                            end
                            onSelesai(true, res)
                        end
                    })
                else
                    if apakahErrorJaringan(res) and percobaanKe < MAX_PERCOBAAN_JARINGAN then
                        mainHandler.postDelayed(Runnable{
                            run = function()
                                jalankanPercobaan(percobaanKe + 1)
                            end
                        }, JEDA_DASAR_RETRY_MS * percobaanKe)
                    else
                        mainHandler.post(Runnable{
                            run = function()
                                if progress then
                                    pcall(function() progress.dismiss() end)
                                end
                                onSelesai(false, res)
                            end
                        })
                    end
                end
            end
        }).start()
    end

    jalankanPercobaan(1)
end

-- ==========================================================
-- PEMBARUAN OTOMATIS SKRIP
-- ==========================================================
prosesDownloadPembaruan = function(kodeBaru)
    local progress = ProgressDialog(service)
    progress.setTitle("Mengunduh pembaruan")
    progress.setMessage("Sedang memasang skrip...")
    progress.setCancelable(true)
    progress.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    progress.show()

    Thread(Runnable{
        run = function()
            local ok, err = pcall(function()
                simpanFilePembaruan(kodeBaru)
            end)

            mainHandler.post(Runnable{
                run = function()
                    pcall(function() progress.dismiss() end)

                    if ok then
                        if service.speak then service.speak("Download selesai. Pembaruan terpasang.") end
                        local d = AlertDialog.Builder(service)
                        d.setTitle("Download selesai")
                        d.setMessage("Pembaruan skrip berhasil dipasang.")
                        d.setPositiveButton("oke", nil)
                        local diag = d.create()
                        diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                        diag.show()
                        aturTombolHurufKecil(diag, "oke", nil, nil)
                    else
                        Toast.makeText(service, "Gagal memasang pembaruan: " .. tostring(err), Toast.LENGTH_LONG).show()
                    end
                end
            })
        end
    }).start()
end

cekPembaruan = function(manual)
    local progress
    if manual then
        progress = ProgressDialog(service)
        progress.setTitle("Periksa versi baru")
        progress.setMessage("Memeriksa ke server GitHub...")
        progress.setCancelable(true)
        progress.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
        progress.show()
    end

    Thread(Runnable{
        run = function()
            local ok, res = pcall(function()
                local url = URL(URL_RAW_SCRIPT)
                local conn = url.openConnection()
                conn.setRequestMethod("GET")
                conn.setRequestProperty("User-Agent", "Android-Accessibility-Manager")
                conn.setConnectTimeout(10000)
                conn.setReadTimeout(15000)

                local respCode = conn.getResponseCode()
                if respCode == 200 then
                    local reader = BufferedReader(InputStreamReader(conn.getInputStream(), "UTF-8"))
                    local lines = {}
                    local line = reader.readLine()
                    while line ~= nil do
                        table.insert(lines, tostring(line))
                        line = reader.readLine()
                    end
                    reader.close()
                    return table.concat(lines, "\n")
                else
                    error("Kode HTTP: " .. respCode)
                end
            end)

            mainHandler.post(Runnable{
                run = function()
                    if progress then
                        pcall(function() progress.dismiss() end)
                    end

                    if ok then
                        local kodeRemote = res
                        local versiBaru = kodeRemote:match('VERSI_SAAT_INI%s*=%s*["\'](.-)["\']')

                        if versiBaru and bandingkanVersi(versiBaru, VERSI_SAAT_INI) then
                            local pesan = "Versi baru: " .. versiBaru .. "\nVersi digunakan: " .. VERSI_SAAT_INI
                            if service.speak then
                                service.speak("Versi baru tersedia " .. versiBaru .. ". Versi yang digunakan " .. VERSI_SAAT_INI)
                            end

                            local d = AlertDialog.Builder(service)
                            d.setTitle("Versi baru tersedia")
                            d.setMessage(pesan)
                            d.setPositiveButton("perbarui", DialogInterface.OnClickListener{
                                onClick = function()
                                    prosesDownloadPembaruan(kodeRemote)
                                end
                            })
                            d.setNegativeButton("nanti", nil)
                            local diag = d.create()
                            diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                            diag.show()
                            aturTombolHurufKecil(diag, "perbarui", "nanti", nil)
                        else
                            if manual then
                                if service.speak then service.speak("Versi baru tidak tersedia.") end
                                local d = AlertDialog.Builder(service)
                                d.setTitle("Periksa versi")
                                d.setMessage("Versi baru tidak tersedia.")
                                d.setPositiveButton("oke", nil)
                                local diag = d.create()
                                diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                                diag.show()
                                aturTombolHurufKecil(diag, "oke", nil, nil)
                            end
                        end
                    else
                        if manual then
                            Toast.makeText(service, "Gagal periksa pembaruan: " .. tostring(res), Toast.LENGTH_LONG).show()
                        end
                    end
                end
            })
        end
    }).start()
end

aktifkanGitHubPagesOtomatis = function(fullName, branchName, token, callback)
    local sourceObj = JSONObject()
    sourceObj.put("branch", branchName)
    sourceObj.put("path", "/")

    local payload = JSONObject()
    payload.put("source", sourceObj)

    local endpoint = "https://api.github.com/repos/" .. fullName .. "/pages"
    kirimPermintaanGitHub("POST", endpoint, token, payload.toString(), function(ok, res)
        if ok then
            local pObj = JSONObject(res)
            callback(true, pObj.optString("html_url", ""))
        else
            callback(false, tostring(res))
        end
    end, true)
end

-- ==========================================================
-- 1. DAFTAR & PENCARIAN REPOSITORI
-- ==========================================================
daftarRepoSayaDialog = function(token, filterAktif)
    filterAktif = filterAktif or "semua"

    local endpoint = "https://api.github.com/user/repos?sort=updated&direction=desc&per_page=100&affiliation=owner"
    kirimPermintaanGitHub("GET", endpoint, token, nil, function(ok, res)
        if not ok then
            Toast.makeText(service, "Gagal memuat: " .. tostring(res), Toast.LENGTH_LONG).show()
            return
        end

        local okProses, hasilData = pcall(function()
            local arr = JSONArray(res)
            local total = arr.length()
            local repoDataListSemua = {}
            for i = 0, total - 1 do
                table.insert(repoDataListSemua, arr.getJSONObject(i))
            end

            table.sort(repoDataListSemua, function(a, b)
                return ambilWaktuTerakhirEdit(a) > ambilWaktuTerakhirEdit(b)
            end)

            local repoDataList = {}
            for _, item in ipairs(repoDataListSemua) do
                local isPrivate = item.optBoolean("private", false)
                if filterAktif == "publik" then
                    if not isPrivate then table.insert(repoDataList, item) end
                elseif filterAktif == "privat" then
                    if isPrivate then table.insert(repoDataList, item) end
                else
                    table.insert(repoDataList, item)
                end
            end

            if filterAktif == "nama" then
                table.sort(repoDataList, function(a, b)
                    return a.optString("name", ""):lower() < b.optString("name", ""):lower()
                end)
            end

            return {dataSemua = repoDataListSemua, data = repoDataList}
        end)

        if not okProses or not hasilData then
            Toast.makeText(service, "Gagal memproses repositori.", Toast.LENGTH_SHORT).show()
            return
        end

        local repoDataListSemua = hasilData.dataSemua
        local repoDataList = hasilData.data
        local totalSemua = #repoDataListSemua
        local total = #repoDataList

        if totalSemua == 0 then
            if service.speak then service.speak("Belum ada repositori.") end
            Toast.makeText(service, "Belum ada repositori.", Toast.LENGTH_SHORT).show()
            menuUtama()
            return
        end

        if service.speak then service.speak("Ditemukan " .. total .. " repositori.") end

        local labelFilter = "Semua"
        if filterAktif == "publik" then labelFilter = "Publik"
        elseif filterAktif == "privat" then labelFilter = "Privat"
        elseif filterAktif == "nama" then labelFilter = "Nama (A-Z)" end

        local listItemsTampil = {
            "Segarkan daftar",
            "Filter: " .. labelFilter .. " (ketuk untuk ganti)",
            "Pilih banyak (multi-select)"
        }
        local offsetItemTetap = #listItemsTampil

        if total == 0 then
            table.insert(listItemsTampil, "(tidak ada repositori dengan filter ini)")
        else
            for i, item in ipairs(repoDataList) do
                local nama = item.optString("name", "")
                local status = item.optBoolean("private", false) and "[privat]" or "[publik]"
                table.insert(listItemsTampil, string.format("%d. %s %s", i, nama, status))
            end
        end

        local b = AlertDialog.Builder(service)
        b.setTitle("Repositori saya (" .. total .. "/" .. totalSemua .. ") - " .. labelFilter)
        b.setItems(listItemsTampil, DialogInterface.OnClickListener{
            onClick = function(dialog, which)
                if which == 0 then
                    if service.speak then service.speak("Menyegarkan daftar repositori.") end
                    daftarRepoSayaDialog(token, filterAktif)
                elseif which == 1 then
                    filterRepoDialog(token, filterAktif)
                elseif which == 2 then
                    if total == 0 then
                        Toast.makeText(service, "Tidak ada repositori untuk dipilih.", Toast.LENGTH_SHORT).show()
                        daftarRepoSayaDialog(token, filterAktif)
                    else
                        multiSelectRepoDialog(token, repoDataList, filterAktif, {})
                    end
                elseif total == 0 then
                    daftarRepoSayaDialog(token, filterAktif)
                else
                    local idx = which - offsetItemTetap + 1
                    kelolaRepoPilihanDialog(repoDataList[idx], token)
                end
            end
        })
        b.setNegativeButton("kembali", DialogInterface.OnClickListener{
            onClick = function() menuUtama() end
        })
        local diag = b.create()
        diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
        diag.show()
        aturTombolHurufKecil(diag, nil, "kembali", nil)
    end)
end

filterRepoDialog = function(token, filterAktifSaatIni)
    local opsi = {"Semua repositori", "Publik saja", "Privat saja", "Urutkan nama (A-Z)"}
    local b = AlertDialog.Builder(service)
    b.setTitle("Filter repositori")
    b.setItems(opsi, DialogInterface.OnClickListener{
        onClick = function(dialog, which)
            if which == 0 then
                daftarRepoSayaDialog(token, "semua")
            elseif which == 1 then
                daftarRepoSayaDialog(token, "publik")
            elseif which == 2 then
                daftarRepoSayaDialog(token, "privat")
            elseif which == 3 then
                daftarRepoSayaDialog(token, "nama")
            end
        end
    })
    b.setNegativeButton("kembali", DialogInterface.OnClickListener{
        onClick = function() daftarRepoSayaDialog(token, filterAktifSaatIni) end
    })
    local diag = b.create()
    diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    diag.show()
    aturTombolHurufKecil(diag, nil, "kembali", nil)
end

multiSelectRepoDialog = function(token, repoDataList, filterAktif, terpilihMap)
    local items = {}
    local jumlahTerpilih = 0
    for i, item in ipairs(repoDataList) do
        local nama = item.optString("name", "")
        local fullName = item.optString("full_name", "")
        local status = item.optBoolean("private", false) and "[privat]" or "[publik]"
        local keteranganCentang = terpilihMap[fullName] and "dicentang" or "tidak dicentang"
        if terpilihMap[fullName] then jumlahTerpilih = jumlahTerpilih + 1 end
        table.insert(items, nama .. " " .. status .. ", " .. keteranganCentang)
    end

    local b = AlertDialog.Builder(service)
    b.setTitle("Pilih banyak repo (" .. jumlahTerpilih .. " terpilih)")
    b.setItems(items, DialogInterface.OnClickListener{
        onClick = function(dialog, which)
            local item = repoDataList[which + 1]
            local nama = item.optString("name", "")
            local fullName = item.optString("full_name", "")
            terpilihMap[fullName] = not terpilihMap[fullName]

            if service.speak then
                if terpilihMap[fullName] then
                    service.speak(nama .. " dicentang")
                else
                    service.speak(nama .. " tidak dicentang")
                end
            end

            multiSelectRepoDialog(token, repoDataList, filterAktif, terpilihMap)
        end
    })
    b.setPositiveButton("hapus terpilih", DialogInterface.OnClickListener{
        onClick = function()
            local daftarFullName = {}
            for fn, dipilih in pairs(terpilihMap) do
                if dipilih then table.insert(daftarFullName, fn) end
            end
            if #daftarFullName == 0 then
                Toast.makeText(service, "Belum ada repositori dipilih.", Toast.LENGTH_SHORT).show()
                multiSelectRepoDialog(token, repoDataList, filterAktif, terpilihMap)
                return
            end

            local konfirm = AlertDialog.Builder(service)
            konfirm.setTitle("Hapus " .. #daftarFullName .. " repositori?")
            konfirm.setMessage("Repositori berikut akan dihapus permanen dari GitHub:\n\n" .. table.concat(daftarFullName, "\n"))
            konfirm.setPositiveButton("hapus semua", DialogInterface.OnClickListener{
                onClick = function()
                    prosesHapusBanyakRepo(token, daftarFullName, filterAktif)
                end
            })
            konfirm.setNegativeButton("batal", DialogInterface.OnClickListener{
                onClick = function() multiSelectRepoDialog(token, repoDataList, filterAktif, terpilihMap) end
            })
            local dK = konfirm.create()
            dK.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
            dK.show()
            aturTombolHurufKecil(dK, "hapus semua", "batal", nil)
        end
    })
    b.setNeutralButton("ubah privasi terpilih", DialogInterface.OnClickListener{
        onClick = function()
            local daftarFullName = {}
            for fn, dipilih in pairs(terpilihMap) do
                if dipilih then table.insert(daftarFullName, fn) end
            end
            if #daftarFullName == 0 then
                Toast.makeText(service, "Belum ada repositori dipilih.", Toast.LENGTH_SHORT).show()
                multiSelectRepoDialog(token, repoDataList, filterAktif, terpilihMap)
                return
            end

            local pilihStatus = AlertDialog.Builder(service)
            pilihStatus.setTitle("Ubah privasi " .. #daftarFullName .. " repositori menjadi:")
            pilihStatus.setItems({"Jadikan publik", "Jadikan privat"}, DialogInterface.OnClickListener{
                onClick = function(d2, which2)
                    local targetPrivat = (which2 == 1)
                    prosesUbahPrivasiBanyakRepo(token, daftarFullName, targetPrivat, filterAktif)
                end
            })
            pilihStatus.setNegativeButton("batal", DialogInterface.OnClickListener{
                onClick = function() multiSelectRepoDialog(token, repoDataList, filterAktif, terpilihMap) end
            })
            local dP = pilihStatus.create()
            dP.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
            dP.show()
            aturTombolHurufKecil(dP, nil, "batal", nil)
        end
    })
    b.setNegativeButton("kembali", DialogInterface.OnClickListener{
        onClick = function() daftarRepoSayaDialog(token, filterAktif) end
    })
    local diag = b.create()
    diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    diag.show()
    aturTombolHurufKecil(diag, "hapus terpilih", "kembali", "ubah privasi terpilih")
end

jalankanOperasiBanyakRepo = function(daftarFullName, judulOperasi, fungsiPerRepo, callbackSelesai)
    local progress = ProgressDialog(service)
    progress.setTitle(judulOperasi)
    progress.setCancelable(false)
    progress.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    progress.show()

    local total = #daftarFullName
    local listSukses = {}
    local listGagal = {}

    local function lanjut(indexKe)
        if indexKe > total then
            pcall(function() progress.dismiss() end)
            callbackSelesai(listSukses, listGagal)
            return
        end

        local fullName = daftarFullName[indexKe]
        pcall(function()
            progress.setMessage("(" .. indexKe .. "/" .. total .. ") " .. fullName)
        end)

        fungsiPerRepo(fullName, function(ok, res)
            if ok then
                table.insert(listSukses, fullName)
            else
                table.insert(listGagal, fullName .. " (" .. tostring(res) .. ")")
            end
            lanjut(indexKe + 1)
        end)
    end

    lanjut(1)
end

prosesHapusBanyakRepo = function(token, daftarFullName, filterAktif)
    jalankanOperasiBanyakRepo(daftarFullName, "Menghapus repositori...", function(fullName, cb)
        local endpoint = "https://api.github.com/repos/" .. fullName
        kirimPermintaanGitHub("DELETE", endpoint, token, nil, cb, true)
    end, function(listSukses, listGagal)
        tampilkanHasilOperasiBanyak("Hapus repositori", listSukses, listGagal, token, filterAktif)
    end)
end

prosesUbahPrivasiBanyakRepo = function(token, daftarFullName, targetPrivat, filterAktif)
    jalankanOperasiBanyakRepo(daftarFullName, "Mengubah privasi...", function(fullName, cb)
        local endpoint = "https://api.github.com/repos/" .. fullName
        local payload = JSONObject()
        payload.put("private", targetPrivat)
        kirimPermintaanGitHub("PATCH", endpoint, token, payload.toString(), cb, true)
    end, function(listSukses, listGagal)
        tampilkanHasilOperasiBanyak("Ubah privasi repositori", listSukses, listGagal, token, filterAktif)
    end)
end

tampilkanHasilOperasiBanyak = function(judul, listSukses, listGagal, token, filterAktif)
    local pesan = "Berhasil: " .. #listSukses .. "\nGagal: " .. #listGagal
    if #listGagal > 0 then
        pesan = pesan .. "\n\nDetail gagal:\n" .. table.concat(listGagal, "\n")
    end

    if service.speak then
        service.speak(judul .. " selesai. Berhasil " .. #listSukses .. ", gagal " .. #listGagal)
    end

    local d = AlertDialog.Builder(service)
    d.setTitle(judul .. " selesai")
    d.setMessage(pesan)
    d.setPositiveButton("oke", DialogInterface.OnClickListener{
        onClick = function() daftarRepoSayaDialog(token, filterAktif) end
    })
    local diag = d.create()
    diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    diag.show()
    aturTombolHurufKecil(diag, "oke", nil, nil)
end

cariRepoDialog = function(token)
    local layout = LinearLayout(service)
    layout.setOrientation(LinearLayout.VERTICAL)
    layout.setPadding(40, 20, 40, 10)

    local input = EditText(service)
    input.setHint("Ketik nama repositori...")
    input.setSingleLine(true)
    layout.addView(input)

    local scroll = ScrollView(service.getApplicationContext())
    scroll.setFillViewport(true)
    scroll.addView(layout)

    local b = AlertDialog.Builder(service)
    b.setTitle("Cari repositori")
    b.setMessage("Masukkan kata kunci nama repositori:")
    b.setView(scroll)
    b.setPositiveButton("cari", DialogInterface.OnClickListener{
        onClick = function()
            local query = tostring(input.getText()):match("^%s*(.-)%s*$"):lower()
            if query == "" then
                Toast.makeText(service, "Kata kunci tidak boleh kosong!", Toast.LENGTH_SHORT).show()
                cariRepoDialog(token)
                return
            end

            local endpoint = "https://api.github.com/user/repos?sort=updated&direction=desc&per_page=100&affiliation=owner"
            kirimPermintaanGitHub("GET", endpoint, token, nil, function(ok, res)
                if not ok then
                    Toast.makeText(service, "Gagal mencari: " .. tostring(res), Toast.LENGTH_LONG).show()
                    return
                end

                local okFilter, hasilFilter = pcall(function()
                    local arr = JSONArray(res)
                    local total = arr.length()
                    local hasilData = {}

                    for i = 0, total - 1 do
                        local item = arr.getJSONObject(i)
                        local nama = item.optString("name", "")
                        if nama:lower():find(query, 1, true) then
                            table.insert(hasilData, item)
                        end
                    end

                    table.sort(hasilData, function(a, b)
                        return ambilWaktuTerakhirEdit(a) > ambilWaktuTerakhirEdit(b)
                    end)

                    local hasilItems = {}
                    for i, item in ipairs(hasilData) do
                        local nama = item.optString("name", "")
                        local status = item.optBoolean("private", false) and "[privat]" or "[publik]"
                        table.insert(hasilItems, string.format("%d. %s %s", i, nama, status))
                    end

                    return {list = hasilItems, data = hasilData}
                end)

                if not okFilter or not hasilFilter or #hasilFilter.data == 0 then
                    if service.speak then service.speak("Tidak ada repositori yang cocok.") end
                    Toast.makeText(service, "Repositori tidak ditemukan.", Toast.LENGTH_SHORT).show()
                    cariRepoDialog(token)
                    return
                end

                local hasilItems = hasilFilter.list
                local hasilData = hasilFilter.data

                if service.speak then service.speak("Ditemukan " .. #hasilItems .. " repositori cocok.") end

                local resB = AlertDialog.Builder(service)
                resB.setTitle("Hasil pencarian (" .. #hasilItems .. ")")
                resB.setItems(hasilItems, DialogInterface.OnClickListener{
                    onClick = function(dRes, whichRes)
                        kelolaRepoPilihanDialog(hasilData[whichRes + 1], token)
                    end
                })
                resB.setNegativeButton("kembali", DialogInterface.OnClickListener{
                    onClick = function() cariRepoDialog(token) end
                })
                local dHasil = resB.create()
                dHasil.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                dHasil.show()
                aturTombolHurufKecil(dHasil, nil, "kembali", nil)
            end)
        end
    })
    b.setNegativeButton("kembali", DialogInterface.OnClickListener{
        onClick = function() menuUtama() end
    })

    local diag = b.create()
    diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    diag.show()
    aturTombolHurufKecil(diag, "cari", "kembali", nil)
end

-- ==========================================================
-- 2. MENU PENGELOLAAN REPOSITORI
-- ==========================================================
kelolaRepoPilihanDialog = function(repoObj, token)
    local namaRepo = repoObj.optString("name", "")
    local fullName = repoObj.optString("full_name", "")
    local htmlUrl = repoObj.optString("html_url", "")
    local isPrivate = repoObj.optBoolean("private", false)

    local subMenus = {
        "1. Buka berkas",
        "2. Tambah berkas (ketik teks)",
        "3. Unggah berkas dari HP",
        "4. Ubah status privasi (" .. (isPrivate and "saat ini privat" or "saat ini publik") .. ")",
        "5. Ganti nama repo",
        "6. Salin tautan repo",
        "7. Bagikan tautan repo",
        "8. Buka di browser",
        "9. Hapus repositori"
    }

    local b = AlertDialog.Builder(service)
    b.setTitle("Repo: " .. namaRepo)
    b.setItems(subMenus, DialogInterface.OnClickListener{
        onClick = function(dialog, which)
            if which == 0 then
                bukaDirektoriRepoDialog(fullName, "", token, repoObj)
            elseif which == 1 then
                tambahFileRepoDialog(token, fullName, repoObj)
            elseif which == 2 then
                unggahDariMemoriHPDialog(fullName, token, repoObj, Environment.getExternalStorageDirectory().getAbsolutePath())
            elseif which == 3 then
                ubahPrivasiRepoDialog(repoObj, token)
            elseif which == 4 then
                gantiNamaRepoDialog(repoObj, token)
            elseif which == 5 then
                salinKeClipboard("Tautan repo", htmlUrl)
            elseif which == 6 then
                bagikanTautan("Repo: " .. namaRepo, htmlUrl)
            elseif which == 7 then
                bukaBrowser(htmlUrl)
            elseif which == 8 then
                hapusRepoDialog(repoObj, token)
            end
        end
    })
    b.setNegativeButton("kembali", DialogInterface.OnClickListener{
        onClick = function() daftarRepoSayaDialog(token) end
    })
    local diag = b.create()
    diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    diag.show()
    aturTombolHurufKecil(diag, nil, "kembali", nil)
end

ubahPrivasiRepoDialog = function(repoObj, token)
    local namaRepo = repoObj.optString("name", "")
    local fullName = repoObj.optString("full_name", "")
    local isPrivate = repoObj.optBoolean("private", false)
    local targetStatusTeks = isPrivate and "publik" or "privat"

    local b = AlertDialog.Builder(service)
    b.setTitle("Ubah privasi repo")
    b.setMessage("Status saat ini: " .. (isPrivate and "Privat" or "Publik") ..
        ".\n\nApakah Anda yakin ingin mengubah repositori ini menjadi " .. targetStatusTeks .. "?")
    b.setPositiveButton("ubah privasi", DialogInterface.OnClickListener{
        onClick = function()
            local payload = JSONObject()
            payload.put("private", not isPrivate)

            local endpoint = "https://api.github.com/repos/" .. fullName
            kirimPermintaanGitHub("PATCH", endpoint, token, payload.toString(), function(ok, res)
                if ok then
                    local updatedObj = JSONObject(res)
                    if service.speak then service.speak("Status repositori diubah menjadi " .. targetStatusTeks) end
                    Toast.makeText(service, "Privasi diubah menjadi " .. targetStatusTeks .. "!", Toast.LENGTH_SHORT).show()
                    kelolaRepoPilihanDialog(updatedObj, token)
                else
                    Toast.makeText(service, "Gagal mengubah privasi: " .. tostring(res), Toast.LENGTH_LONG).show()
                    kelolaRepoPilihanDialog(repoObj, token)
                end
            end)
        end
    })
    b.setNegativeButton("kembali", DialogInterface.OnClickListener{
        onClick = function() kelolaRepoPilihanDialog(repoObj, token) end
    })

    local diag = b.create()
    diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    diag.show()
    aturTombolHurufKecil(diag, "ubah privasi", "kembali", nil)
end

konfirmUnggahBerkasDialog = function(fullName, token, repoObj, pathSekarang, terpilih)
    local layoutKonfirm = LinearLayout(service)
    layoutKonfirm.setOrientation(LinearLayout.VERTICAL)
    layoutKonfirm.setPadding(40, 20, 40, 10)

    local lblTarget = TextView(service)
    lblTarget.setText("Nama berkas di GitHub:")
    layoutKonfirm.addView(lblTarget)

    local inputNamaRepo = EditText(service)
    inputNamaRepo.setText(terpilih.getName())
    inputNamaRepo.setSingleLine(true)
    layoutKonfirm.addView(inputNamaRepo)

    local scrollK = ScrollView(service.getApplicationContext())
    scrollK.setFillViewport(true)
    scrollK.addView(layoutKonfirm)

    local dKonfirm = AlertDialog.Builder(service)
    dKonfirm.setTitle("Unggah berkas terpilih")
    dKonfirm.setMessage("Ukuran berkas: " .. formatUkuranBerkas(terpilih.length()))
    dKonfirm.setView(scrollK)
    dKonfirm.setPositiveButton("unggah berkas", DialogInterface.OnClickListener{
        onClick = function()
            local namaDiRepo = tostring(inputNamaRepo.getText()):match("^%s*(.-)%s*$")
            if namaDiRepo == "" then namaDiRepo = terpilih.getName() end

            local okB64, b64Data = pcall(function() return bacaBerkasKeBase64(terpilih) end)
            if not okB64 then
                Toast.makeText(service, "Gagal membaca berkas: " .. tostring(b64Data), Toast.LENGTH_SHORT).show()
                return
            end

            local payload = JSONObject()
            payload.put("message", "Unggah " .. namaDiRepo .. " dari HP")
            payload.put("content", b64Data)

            local endpoint = "https://api.github.com/repos/" .. fullName .. "/contents/" .. namaDiRepo
            kirimPermintaanGitHub("PUT", endpoint, token, payload.toString(), function(sukses, resPut)
                if sukses then
                    local objRes = JSONObject(resPut)
                    local contentObj = objRes.optJSONObject("content")
                    local rawUrl = contentObj and contentObj.optString("download_url", "") or ""
                    local htmlUrl = contentObj and contentObj.optString("html_url", "") or ""

                    local dSukses = AlertDialog.Builder(service)
                    dSukses.setTitle("Berkas berhasil diunggah")
                    dSukses.setMessage("Berkas: " .. namaDiRepo .. "\n\nTautan raw:\n" .. rawUrl .. "\n\nTautan web:\n" .. htmlUrl)
                    dSukses.setPositiveButton("salin tautan raw", DialogInterface.OnClickListener{
                        onClick = function() salinKeClipboard("Tautan raw", rawUrl) end
                    })
                    dSukses.setNeutralButton("bagikan", DialogInterface.OnClickListener{
                        onClick = function() bagikanTautan("Berkas: " .. namaDiRepo, rawUrl) end
                    })
                    dSukses.setNegativeButton("kembali", DialogInterface.OnClickListener{
                        onClick = function() kelolaRepoPilihanDialog(repoObj, token) end
                    })
                    local dS = dSukses.create()
                    dS.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                    dS.show()
                    aturTombolHurufKecil(dS, "salin tautan raw", "kembali", "bagikan")
                else
                    Toast.makeText(service, "Gagal unggah: " .. tostring(resPut), Toast.LENGTH_LONG).show()
                    kelolaRepoPilihanDialog(repoObj, token)
                end
            end)
        end
    })
    dKonfirm.setNegativeButton("kembali", DialogInterface.OnClickListener{
        onClick = function()
            unggahDariMemoriHPDialog(fullName, token, repoObj, pathSekarang)
        end
    })
    local dK = dKonfirm.create()
    dK.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    dK.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
    dK.show()
    aturTombolHurufKecil(dK, "unggah berkas", "kembali", nil)
end

unggahDariMemoriHPDialog = function(fullName, token, repoObj, pathSekarang)
    local dir = File(pathSekarang)
    local files = dir.listFiles()
    local menuItems = {}
    local dataItems = {}

    local rootPath = Environment.getExternalStorageDirectory().getAbsolutePath()
    if pathSekarang ~= rootPath and pathSekarang ~= "/" then
        table.insert(menuItems, "Folder .. (kembali ke folder sebelumnya)")
        table.insert(dataItems, {tipe = "kembali", path = dir.getParent()})
    end

    if files ~= nil then
        local daftarFolder = {}
        local daftarBerkas = {}

        for i = 0, #files - 1 do
            local f = files[i]
            local nama = f.getName()
            if not nama:find("^%.") then
                if f.isDirectory() then
                    table.insert(daftarFolder, f)
                else
                    table.insert(daftarBerkas, f)
                end
            end
        end

        table.sort(daftarFolder, function(a, b) return a.getName():lower() < b.getName():lower() end)
        table.sort(daftarBerkas, function(a, b) return a.getName():lower() < b.getName():lower() end)

        for _, f in ipairs(daftarFolder) do
            table.insert(menuItems, "Folder " .. f.getName())
            table.insert(dataItems, {tipe = "dir", file = f})
        end

        for _, f in ipairs(daftarBerkas) do
            local sz = formatUkuranBerkas(f.length())
            table.insert(menuItems, "Berkas " .. f.getName() .. " (" .. sz .. ")")
            table.insert(dataItems, {tipe = "file", file = f})
        end
    end

    local b = AlertDialog.Builder(service)
    b.setTitle("Pilih dari HP: " .. dir.getName())
    if #menuItems == 0 then
        b.setMessage("Folder ini kosong.")
    else
        b.setItems(menuItems, DialogInterface.OnClickListener{
            onClick = function(diag, which)
                local item = dataItems[which + 1]
                if item.tipe == "kembali" then
                    unggahDariMemoriHPDialog(fullName, token, repoObj, item.path or rootPath)
                elseif item.tipe == "dir" then
                    unggahDariMemoriHPDialog(fullName, token, repoObj, item.file.getAbsolutePath())
                elseif item.tipe == "file" then
                    konfirmUnggahBerkasDialog(fullName, token, repoObj, pathSekarang, item.file)
                end
            end
        })
    end

    b.setNegativeButton("kembali", DialogInterface.OnClickListener{
        onClick = function() kelolaRepoPilihanDialog(repoObj, token) end
    })
    local diag = b.create()
    diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    diag.show()
    aturTombolHurufKecil(diag, nil, "kembali", nil)
end

hapusRepoDialog = function(repoObj, token)
    local namaRepo = repoObj.optString("name", "")
    local fullName = repoObj.optString("full_name", "")

    local b = AlertDialog.Builder(service)
    b.setTitle("Hapus repositori?")
    b.setMessage("Hapus '" .. namaRepo .. "' secara permanen dari GitHub?")
    b.setPositiveButton("hapus repositori", DialogInterface.OnClickListener{
        onClick = function()
            local endpoint = "https://api.github.com/repos/" .. fullName
            kirimPermintaanGitHub("DELETE", endpoint, token, nil, function(ok, res)
                if ok then
                    if service.speak then service.speak("Repositori " .. namaRepo .. " berhasil dihapus.") end
                    Toast.makeText(service, "Repositori dihapus!", Toast.LENGTH_SHORT).show()
                    daftarRepoSayaDialog(token)
                else
                    if service.speak then service.speak("Gagal menghapus.") end
                    local err = tostring(res)
                    if err:find("403") or err:find("404") then
                        err = err .. "\n(Perlu izin token 'delete_repo')"
                    end
                    Toast.makeText(service, err, Toast.LENGTH_LONG).show()
                    kelolaRepoPilihanDialog(repoObj, token)
                end
            end)
        end
    })
    b.setNegativeButton("kembali", DialogInterface.OnClickListener{
        onClick = function() kelolaRepoPilihanDialog(repoObj, token) end
    })

    local diag = b.create()
    diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    diag.show()
    aturTombolHurufKecil(diag, "hapus repositori", "kembali", nil)
end

gantiNamaRepoDialog = function(repoObj, token)
    local namaLama = repoObj.optString("name", "")
    local fullName = repoObj.optString("full_name", "")

    local layout = LinearLayout(service)
    layout.setOrientation(LinearLayout.VERTICAL)
    layout.setPadding(40, 20, 40, 10)

    local lbl = TextView(service)
    lbl.setText("Nama baru repo:")
    layout.addView(lbl)

    local input = EditText(service)
    input.setText(namaLama)
    input.setSingleLine(true)
    layout.addView(input)

    local scroll = ScrollView(service.getApplicationContext())
    scroll.setFillViewport(true)
    scroll.addView(layout)

    local b = AlertDialog.Builder(service)
    b.setTitle("Ganti nama repo")
    b.setView(scroll)
    b.setPositiveButton("simpan nama baru", DialogInterface.OnClickListener{
        onClick = function()
            local baru = tostring(input.getText()):match("^%s*(.-)%s*$")
            if baru == "" or baru == namaLama then
                kelolaRepoPilihanDialog(repoObj, token)
                return
            end

            local payload = JSONObject()
            payload.put("name", baru)

            local endpoint = "https://api.github.com/repos/" .. fullName
            kirimPermintaanGitHub("PATCH", endpoint, token, payload.toString(), function(ok, res)
                if ok then
                    local updatedObj = JSONObject(res)
                    if service.speak then service.speak("Nama repo diubah menjadi " .. baru) end
                    Toast.makeText(service, "Nama repo diperbarui!", Toast.LENGTH_SHORT).show()
                    kelolaRepoPilihanDialog(updatedObj, token)
                else
                    Toast.makeText(service, "Gagal: " .. tostring(res), Toast.LENGTH_LONG).show()
                    kelolaRepoPilihanDialog(repoObj, token)
                end
            end)
        end
    })
    b.setNegativeButton("kembali", DialogInterface.OnClickListener{
        onClick = function() kelolaRepoPilihanDialog(repoObj, token) end
    })

    local diag = b.create()
    diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    diag.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
    diag.show()
    aturTombolHurufKecil(diag, "simpan nama baru", "kembali", nil)
end

gantiNamaBerkasDialog = function(fullName, fileData, token, currentPath, repoObj)
    local namaLama = fileData.name
    local layout = LinearLayout(service)
    layout.setOrientation(LinearLayout.VERTICAL)
    layout.setPadding(40, 20, 40, 10)

    local lbl = TextView(service)
    lbl.setText("Nama baru berkas:")
    layout.addView(lbl)

    local input = EditText(service)
    input.setText(namaLama)
    input.setSingleLine(true)
    layout.addView(input)

    local scroll = ScrollView(service.getApplicationContext())
    scroll.setFillViewport(true)
    scroll.addView(layout)

    local b = AlertDialog.Builder(service)
    b.setTitle("Ganti nama: " .. namaLama)
    b.setView(scroll)
    b.setPositiveButton("simpan nama baru", DialogInterface.OnClickListener{
        onClick = function()
            local namaBaru = tostring(input.getText()):match("^%s*(.-)%s*$")
            if namaBaru == "" or namaBaru == namaLama then
                menuAksiFile(fullName, fileData, token, currentPath, repoObj)
                return
            end

            local jalurBaru = (currentPath == "") and namaBaru or (currentPath .. "/" .. namaBaru)
            local endpointAmbil = "https://api.github.com/repos/" .. fullName .. "/contents/" .. fileData.path

            kirimPermintaanGitHub("GET", endpointAmbil, token, nil, function(okGet, resGet)
                if not okGet then
                    Toast.makeText(service, "Gagal mengambil berkas: " .. tostring(resGet), Toast.LENGTH_LONG).show()
                    menuAksiFile(fullName, fileData, token, currentPath, repoObj)
                    return
                end

                local objGet = JSONObject(resGet)
                local shaLama = objGet.optString("sha", fileData.sha)
                local contentBase64 = objGet.optString("content", ""):gsub("%s+", "")

                local endpointBaru = "https://api.github.com/repos/" .. fullName .. "/contents/" .. jalurBaru
                local payloadBaru = JSONObject()
                payloadBaru.put("message", "Ganti nama " .. namaLama .. " menjadi " .. namaBaru)
                payloadBaru.put("content", contentBase64)

                kirimPermintaanGitHub("PUT", endpointBaru, token, payloadBaru.toString(), function(okPut, resPut)
                    if not okPut then
                        Toast.makeText(service, "Gagal membuat berkas baru: " .. tostring(resPut), Toast.LENGTH_LONG).show()
                        menuAksiFile(fullName, fileData, token, currentPath, repoObj)
                        return
                    end

                    local endpointHapus = "https://api.github.com/repos/" .. fullName .. "/contents/" .. fileData.path
                    local payloadHapus = JSONObject()
                    payloadHapus.put("message", "Hapus berkas lama setelah ganti nama")
                    payloadHapus.put("sha", shaLama)

                    kirimPermintaanGitHub("DELETE", endpointHapus, token, payloadHapus.toString(), function(okDel, resDel)
                        if okDel then
                            if service.speak then service.speak("Nama berkas berhasil diubah menjadi " .. namaBaru) end
                            Toast.makeText(service, "Nama berkas diperbarui!", Toast.LENGTH_SHORT).show()
                            bukaDirektoriRepoDialog(fullName, currentPath, token, repoObj)
                        else
                            Toast.makeText(service, "Gagal menghapus berkas lama: " .. tostring(resDel), Toast.LENGTH_LONG).show()
                            bukaDirektoriRepoDialog(fullName, currentPath, token, repoObj)
                        end
                    end)
                end)
            end)
        end
    })
    b.setNegativeButton("kembali", DialogInterface.OnClickListener{
        onClick = function()
            menuAksiFile(fullName, fileData, token, currentPath, repoObj)
        end
    })

    local diag = b.create()
    diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    diag.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
    diag.show()
    aturTombolHurufKecil(diag, "simpan nama baru", "kembali", nil)
end

bukaDirektoriRepoDialog = function(fullName, currentPath, token, repoObj)
    local endpoint = "https://api.github.com/repos/" .. fullName .. "/contents/" .. currentPath
    kirimPermintaanGitHub("GET", endpoint, token, nil, function(ok, res)
        if not ok then
            Toast.makeText(service, "Gagal: " .. tostring(res), Toast.LENGTH_LONG).show()
            return
        end

        local itemsArr = JSONArray(res)
        local total = itemsArr.length()
        local menuItems = {}
        local dataItems = {}

        if currentPath ~= "" then
            table.insert(menuItems, "Folder .. (kembali)")
            table.insert(dataItems, {tipe = "kembali_folder"})
        end

        for i = 0, total - 1 do
            local item = itemsArr.getJSONObject(i)
            local tipe = item.optString("type", "")
            local name = item.optString("name", "")
            local awalan = (tipe == "dir") and "Folder " or "Berkas "

            table.insert(menuItems, awalan .. name)
            table.insert(dataItems, {
                tipe = tipe,
                name = name,
                path = item.optString("path", ""),
                sha = item.optString("sha", ""),
                html_url = item.optString("html_url", ""),
                download_url = item.optString("download_url", "")
            })
        end

        local judul = (currentPath == "") and ("Berkas: " .. repoObj.optString("name", "")) or ("Folder: " .. currentPath)
        local b = AlertDialog.Builder(service)
        b.setTitle(judul)

        if #menuItems == 0 then
            b.setMessage("Folder ini kosong.")
        else
            b.setItems(menuItems, DialogInterface.OnClickListener{
                onClick = function(dialog, which)
                    local data = dataItems[which + 1]
                    if data.tipe == "kembali_folder" then
                        local parentPath = currentPath:match("^(.*)/[^/]+$") or ""
                        bukaDirektoriRepoDialog(fullName, parentPath, token, repoObj)
                    elseif data.tipe == "dir" then
                        bukaDirektoriRepoDialog(fullName, data.path, token, repoObj)
                    else
                        menuAksiFile(fullName, data, token, currentPath, repoObj)
                    end
                end
            })
        end

        b.setNegativeButton("kembali", DialogInterface.OnClickListener{
            onClick = function()
                if currentPath == "" then
                    kelolaRepoPilihanDialog(repoObj, token)
                else
                    local parentPath = currentPath:match("^(.*)/[^/]+$") or ""
                    bukaDirektoriRepoDialog(fullName, parentPath, token, repoObj)
                end
            end
        })

        local diag = b.create()
        diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
        diag.show()
        aturTombolHurufKecil(diag, nil, "kembali", nil)
    end)
end

menuAksiFile = function(fullName, fileData, token, currentPath, repoObj)
    local opsiFile = {
        "1. Salin tautan raw (updater)",
        "2. Edit isi berkas",
        "3. Ganti nama berkas",
        "4. Salin tautan web",
        "5. Bagikan tautan raw",
        "6. Hapus berkas"
    }

    local b = AlertDialog.Builder(service)
    b.setTitle("Berkas: " .. fileData.name)
    b.setItems(opsiFile, DialogInterface.OnClickListener{
        onClick = function(dialog, which)
            if which == 0 then
                salinKeClipboard("Tautan raw", fileData.download_url)
            elseif which == 1 then
                local endpoint = "https://api.github.com/repos/" .. fullName .. "/contents/" .. fileData.path
                kirimPermintaanGitHub("GET", endpoint, token, nil, function(ok, res)
                    if ok then
                        local obj = JSONObject(res)
                        local sha = obj.optString("sha", "")
                        local base64Content = obj.optString("content", ""):gsub("%s+", "")
                        local bytes = Base64.decode(base64Content, Base64.DEFAULT)
                        local isiTeks = String(bytes, "UTF-8")

                        formEditIsiBerkas(fullName, fileData.path, sha, isiTeks, token, function()
                            bukaDirektoriRepoDialog(fullName, currentPath, token, repoObj)
                        end, function()
                            menuAksiFile(fullName, fileData, token, currentPath, repoObj)
                        end)
                    else
                        Toast.makeText(service, "Gagal membaca: " .. tostring(res), Toast.LENGTH_LONG).show()
                    end
                end)
            elseif which == 2 then
                gantiNamaBerkasDialog(fullName, fileData, token, currentPath, repoObj)
            elseif which == 3 then
                salinKeClipboard("Tautan web", fileData.html_url)
            elseif which == 4 then
                bagikanTautan("Berkas raw: " .. fileData.name, fileData.download_url)
            elseif which == 5 then
                local konfirm = AlertDialog.Builder(service)
                konfirm.setTitle("Hapus berkas?")
                konfirm.setMessage("Hapus " .. fileData.name .. " dari repositori?")
                konfirm.setPositiveButton("hapus berkas", DialogInterface.OnClickListener{
                    onClick = function()
                        local delEndpoint = "https://api.github.com/repos/" .. fullName .. "/contents/" .. fileData.path
                        local delPayload = JSONObject()
                        delPayload.put("message", "Hapus " .. fileData.name)
                        delPayload.put("sha", fileData.sha)

                        kirimPermintaanGitHub("DELETE", delEndpoint, token, delPayload.toString(), function(sukses, hasilDel)
                            if sukses then
                                if service.speak then service.speak("Berkas dihapus.") end
                                Toast.makeText(service, "Berkas dihapus!", Toast.LENGTH_SHORT).show()
                                bukaDirektoriRepoDialog(fullName, currentPath, token, repoObj)
                            else
                                Toast.makeText(service, "Gagal: " .. tostring(hasilDel), Toast.LENGTH_LONG).show()
                            end
                        end)
                    end
                })
                konfirm.setNegativeButton("kembali", DialogInterface.OnClickListener{
                    onClick = function() menuAksiFile(fullName, fileData, token, currentPath, repoObj) end
                })
                local dKonfirm = konfirm.create()
                dKonfirm.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                dKonfirm.show()
                aturTombolHurufKecil(dKonfirm, "hapus berkas", "kembali", nil)
            end
        end
    })
    b.setNegativeButton("kembali", DialogInterface.OnClickListener{
        onClick = function() bukaDirektoriRepoDialog(fullName, currentPath, token, repoObj) end
    })
    local diag = b.create()
    diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    diag.show()
    aturTombolHurufKecil(diag, nil, "kembali", nil)
end

formEditIsiBerkas = function(repo, path, sha, isiAwal, token, onSuccess, onBatal)
    local layout = LinearLayout(service)
    layout.setOrientation(LinearLayout.VERTICAL)
    layout.setPadding(40, 20, 40, 10)

    local editor = EditText(service)
    editor.setText(isiAwal)
    editor.setMinLines(6)
    layout.addView(editor)

    local scroll = ScrollView(service.getApplicationContext())
    scroll.setFillViewport(true)
    scroll.addView(layout)

    local editBuilder = AlertDialog.Builder(service)
    editBuilder.setTitle("Edit: " .. path)
    editBuilder.setView(scroll)
    editBuilder.setPositiveButton("simpan perubahan", DialogInterface.OnClickListener{
        onClick = function()
            local isiBaru = tostring(editor.getText())
            local encoded = Base64.encodeToString(String(isiBaru).getBytes("UTF-8"), Base64.NO_WRAP)

            local endpoint = "https://api.github.com/repos/" .. repo .. "/contents/" .. path
            local putPayload = JSONObject()
            putPayload.put("message", "Perbarui " .. path)
            putPayload.put("content", encoded)
            putPayload.put("sha", sha)

            kirimPermintaanGitHub("PUT", endpoint, token, putPayload.toString(), function(sukses, hasil)
                if sukses then
                    if service.speak then service.speak("Perubahan disimpan.") end
                    Toast.makeText(service, "Berkas diperbarui!", Toast.LENGTH_SHORT).show()
                    if onSuccess then onSuccess() end
                else
                    Toast.makeText(service, "Gagal: " .. tostring(hasil), Toast.LENGTH_LONG).show()
                end
            end)
        end
    })
    editBuilder.setNegativeButton("kembali", DialogInterface.OnClickListener{
        onClick = function()
            if onBatal then onBatal() else menuUtama() end
        end
    })

    local editDialog = editBuilder.create()
    editDialog.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    editDialog.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
    editDialog.show()
    aturTombolHurufKecil(editDialog, "simpan perubahan", "kembali", nil)
end

-- ==========================================================
-- 3. PEMBUATAN REPOSITORI BARU
-- ==========================================================
buatRepoDialog = function(token)
    local layout = LinearLayout(service)
    layout.setOrientation(LinearLayout.VERTICAL)
    layout.setPadding(40, 20, 40, 10)

    local lblNama = TextView(service)
    lblNama.setText("Nama repo:")
    layout.addView(lblNama)

    local inputNama = EditText(service)
    inputNama.setHint("contoh: skrip-baru")
    inputNama.setSingleLine(true)
    layout.addView(inputNama)

    local lblDesc = TextView(service)
    lblDesc.setText("Deskripsi:")
    lblDesc.setPadding(0, 15, 0, 0)
    layout.addView(lblDesc)

    local inputDesc = EditText(service)
    inputDesc.setHint("Keterangan singkat")
    inputDesc.setSingleLine(true)
    layout.addView(inputDesc)

    local chkPrivate = CheckBox(service)
    chkPrivate.setText("Jadikan privat")
    layout.addView(chkPrivate)

    local chkReadme = CheckBox(service)
    chkReadme.setText("Tambahkan README")
    chkReadme.setChecked(false)
    layout.addView(chkReadme)

    local scroll = ScrollView(service.getApplicationContext())
    scroll.setFillViewport(true)
    scroll.addView(layout)

    local b = AlertDialog.Builder(service)
    b.setTitle("Buat repositori baru")
    b.setView(scroll)
    b.setPositiveButton("buat repositori", DialogInterface.OnClickListener{
        onClick = function()
            local nama = tostring(inputNama.getText()):match("^%s*(.-)%s*$")
            local desc = tostring(inputDesc.getText()):match("^%s*(.-)%s*$")
            if nama == "" then
                if service.speak then service.speak("Nama repo wajib diisi.") end
                return
            end

            local isPrivat = chkPrivate.isChecked()
            local payload = JSONObject()
            payload.put("name", nama)
            payload.put("description", desc)
            payload.put("private", isPrivat)
            local pakaiReadme = chkReadme.isChecked()
            payload.put("auto_init", pakaiReadme)

            kirimPermintaanGitHub("POST", "https://api.github.com/user/repos", token, payload.toString(), function(ok, res)
                if ok then
                    local obj = JSONObject(res)
                    local fullName = obj.optString("full_name", "")
                    local defaultBranch = obj.optString("default_branch", "main")
                    local htmlUrl = obj.optString("html_url", "")

                    mainHandler.postDelayed(Runnable{
                        run = function()
                            local function tampilHasil(suksesPages, infoPages)
                                local pesanDialog = "Nama: " .. obj.optString("name", "") .. "\nTautan: " .. htmlUrl
                                if suksesPages then
                                    pesanDialog = pesanDialog .. "\n\nGitHub Pages aktif:\n" .. infoPages
                                    if service.speak then service.speak("Repositori dan Pages berhasil diaktifkan.") end
                                else
                                    if service.speak then service.speak("Repositori berhasil dibuat.") end
                                end

                                local d = AlertDialog.Builder(service)
                                d.setTitle("Repositori dibuat")
                                d.setMessage(pesanDialog)
                                d.setPositiveButton("salin tautan", DialogInterface.OnClickListener{
                                    onClick = function() salinKeClipboard("Tautan repo", htmlUrl) end
                                })
                                d.setNeutralButton("bagikan", DialogInterface.OnClickListener{
                                    onClick = function() bagikanTautan("Repo: " .. nama, htmlUrl) end
                                })
                                d.setNegativeButton("kembali", DialogInterface.OnClickListener{
                                    onClick = function() menuUtama() end
                                })
                                local diag = d.create()
                                diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                                diag.show()
                                aturTombolHurufKecil(diag, "salin tautan", "kembali", "bagikan")
                            end
                            if pakaiReadme then
                                aktifkanGitHubPagesOtomatis(fullName, defaultBranch, token, tampilHasil)
                            else
                                tampilHasil(false, "")
                            end
                        end
                    }, 1500)
                else
                    if service.speak then service.speak("Gagal membuat repo.") end
                    Toast.makeText(service, tostring(res), Toast.LENGTH_LONG).show()
                end
            end)
        end
    })
    b.setNegativeButton("kembali", DialogInterface.OnClickListener{
        onClick = function() menuUtama() end
    })

    local diag = b.create()
    diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    diag.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
    diag.show()
    aturTombolHurufKecil(diag, "buat repositori", "kembali", nil)
end

tambahFileRepoDialog = function(token, repoOtomatis, repoObj)
    local layout = LinearLayout(service)
    layout.setOrientation(LinearLayout.VERTICAL)
    layout.setPadding(40, 20, 40, 10)

    local lblRepo = TextView(service)
    lblRepo.setText("Nama repo:")
    layout.addView(lblRepo)

    local inputRepo = EditText(service)
    inputRepo.setHint("username/nama-repo")
    inputRepo.setSingleLine(true)
    if repoOtomatis then
        inputRepo.setText(repoOtomatis)
    end
    layout.addView(inputRepo)

    local lblPath = TextView(service)
    lblPath.setText("Nama berkas:")
    lblPath.setPadding(0, 15, 0, 0)
    layout.addView(lblPath)

    local inputPath = EditText(service)
    inputPath.setHint("contoh: main.lua")
    inputPath.setSingleLine(true)
    layout.addView(inputPath)

    local lblKonten = TextView(service)
    lblKonten.setText("Isi berkas:")
    lblKonten.setPadding(0, 15, 0, 0)
    layout.addView(lblKonten)

    local inputKonten = EditText(service)
    inputKonten.setHint("Ketik / tempel isi berkas...")
    inputKonten.setMinLines(5)
    layout.addView(inputKonten)

    local scroll = ScrollView(service.getApplicationContext())
    scroll.setFillViewport(true)
    scroll.addView(layout)

    local b = AlertDialog.Builder(service)
    b.setTitle("Tambah berkas baru")
    b.setView(scroll)
    b.setPositiveButton("simpan berkas", DialogInterface.OnClickListener{
        onClick = function()
            local repo = tostring(inputRepo.getText()):match("^%s*(.-)%s*$")
            local path = tostring(inputPath.getText()):match("^%s*(.-)%s*$")
            local konten = tostring(inputKonten.getText())

            if repo == "" or path == "" then
                Toast.makeText(service, "Nama repo dan nama berkas wajib diisi!", Toast.LENGTH_SHORT).show()
                return
            end

            local kontenBase64 = Base64.encodeToString(String(konten).getBytes("UTF-8"), Base64.NO_WRAP)
            local payload = JSONObject()
            payload.put("message", "Tambah " .. path)
            payload.put("content", kontenBase64)

            local endpoint = "https://api.github.com/repos/" .. repo .. "/contents/" .. path
            kirimPermintaanGitHub("PUT", endpoint, token, payload.toString(), function(ok, res)
                if ok then
                    local obj = JSONObject(res)
                    local contentObj = obj.optJSONObject("content")
                    local fileUrl = contentObj and contentObj.optString("html_url", "") or ""
                    local rawUrl = contentObj and contentObj.optString("download_url", "") or ""

                    local d = AlertDialog.Builder(service)
                    d.setTitle("Berkas ditambahkan")
                    d.setMessage("Nama: " .. path .. "\n\nTautan raw:\n" .. rawUrl .. "\n\nTautan web:\n" .. fileUrl)
                    d.setPositiveButton("salin tautan raw", DialogInterface.OnClickListener{
                        onClick = function() salinKeClipboard("Tautan raw", rawUrl) end
                    })
                    d.setNeutralButton("bagikan", DialogInterface.OnClickListener{
                        onClick = function() bagikanTautan("Berkas: " .. path, rawUrl) end
                    })
                    d.setNegativeButton("kembali", DialogInterface.OnClickListener{
                        onClick = function()
                            if repoObj then
                                kelolaRepoPilihanDialog(repoObj, token)
                            else
                                menuUtama()
                            end
                        end
                    })
                    local diag = d.create()
                    diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                    diag.show()
                    aturTombolHurufKecil(diag, "salin tautan raw", "kembali", "bagikan")
                else
                    Toast.makeText(service, "Gagal: " .. tostring(res), Toast.LENGTH_LONG).show()
                end
            end)
        end
    })
    b.setNegativeButton("kembali", DialogInterface.OnClickListener{
        onClick = function()
            if repoObj then
                kelolaRepoPilihanDialog(repoObj, token)
            else
                menuUtama()
            end
        end
    })

    local diag = b.create()
    diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    diag.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
    diag.show()
    aturTombolHurufKecil(diag, "simpan berkas", "kembali", nil)
end

-- ==========================================================
-- 4. PEMBUAT APLIKASI APK - PUSAT CI/CD ACTIONS LENGKAP
-- ==========================================================
local PembuatAPK = {}
local KEY_DAFTAR_APLIKASI = "key_daftar_aplikasi_apk_unik"
local NAMA_ALUR_KERJA = "bangun-apk.yml"

local TEMPLAT = {}

TEMPLAT.settings = [==[
import org.gradle.api.initialization.resolve.RepositoriesMode

pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "@@NAMA_PROYEK@@"
include ':app'
]==]

TEMPLAT.buildRoot = [==[
plugins {
    id 'com.android.application' version '8.6.1' apply false
    id 'org.jetbrains.kotlin.android' version '1.9.24' apply false
}
]==]

TEMPLAT.gradleProps = [==[
org.gradle.jvmargs=-Xmx2g -Dfile.encoding=UTF-8
android.useAndroidX=true
android.enableJetifier=true
android.nonTransitiveRClass=true
]==]

TEMPLAT.buildApp = [==[
plugins {
    id 'com.android.application'
    @@KOTLIN_PLUGIN@@
}

android {
    namespace '@@PAKET@@'
    compileSdk @@COMPILE_SDK@@
    defaultConfig {
        applicationId '@@PAKET@@'
        minSdk @@MIN_SDK@@
        targetSdk @@TARGET_SDK@@
        versionCode @@VERSION_CODE@@
        versionName '@@VERSI@@'
        testInstrumentationRunner 'androidx.test.runner.AndroidJUnitRunner'
    }

    buildTypes {
        debug { debuggable true; applicationIdSuffix '.debug'; versionNameSuffix '-debug' }
        release {
            minifyEnabled @@MINIFY@@
            shrinkResources @@SHRINK@@
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
        staging {
            initWith debug
            applicationIdSuffix '.staging'
            versionNameSuffix '-staging'
            matchingFallbacks = ['debug']
        }
    }

    flavorDimensions 'versi'
    productFlavors {
        gratis { dimension 'versi'; applicationIdSuffix '.gratis'; versionNameSuffix '-gratis' }
        pro { dimension 'versi'; applicationIdSuffix '.pro'; versionNameSuffix '-pro' }
    }

    signingConfigs {
        release {
            def ks = System.getenv('KEYSTORE_FILE')
            def kp = System.getenv('KEYSTORE_PASSWORD')
            def ka = System.getenv('KEY_ALIAS')
            def pp = System.getenv('KEY_PASSWORD')
            if (ks && kp && ka && pp) {
                storeFile file(ks); storePassword kp; keyAlias ka; keyPassword pp
            }
        }
    }
    if (System.getenv('KEYSTORE_FILE') && System.getenv('KEYSTORE_PASSWORD') && System.getenv('KEY_ALIAS') && System.getenv('KEY_PASSWORD')) {
        buildTypes.release.signingConfig signingConfigs.release
    }

    splits {
        abi {
            enable @@ABI_SPLIT@@
            reset()
            include @@ABI_INCLUDE@@
            universalApk true
        }
    }

    compileOptions { sourceCompatibility JavaVersion.VERSION_17; targetCompatibility JavaVersion.VERSION_17 }
    @@KOTLIN_OPTIONS@@
    buildFeatures { viewBinding true; compose @@COMPOSE_ENABLED@@ }
    @@COMPOSE_OPTIONS@@
    lint {
        abortOnError false
        checkReleaseBuilds false
    }
    packaging.resources.excludes += ['/META-INF/{AL2.0,LGPL2.1}', '/META-INF/LICENSE*', '/META-INF/NOTICE*']
}

dependencies {
    implementation 'androidx.core:core-ktx:1.13.1'
    implementation 'androidx.appcompat:appcompat:1.7.0'
    implementation 'com.google.android.material:material:1.12.0'
@@DEPENDENCIES@@
    testImplementation 'junit:junit:4.13.2'
    androidTestImplementation 'androidx.test.ext:junit:1.2.1'
    androidTestImplementation 'androidx.test.espresso:espresso-core:3.6.1'
}
]==]

TEMPLAT.proguard = [==[
# Aturan ProGuard untuk optimasi R8
-keepattributes *Annotation*
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
]==]

TEMPLAT.manifest = [==[
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
@@IZIN@@
    <application
        android:label="@string/app_name"
        android:icon="@drawable/ikon_aplikasi"
        android:allowBackup="@@BACKUP@@"
        android:supportsRtl="true"
        android:usesCleartextTraffic="@@CLEAR_TEXT@@"
        android:theme="@@TEMA@@">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:screenOrientation="@@ORIENTASI@@"
            android:configChanges="orientation|screenSize|keyboardHidden">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
@@COMPONENTS@@
    </application>
</manifest>
]==]

TEMPLAT.strings = [==[
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">@@NAMA_XML@@</string>
    <color name="ikon_warna">@@WARNA_IKON@@</color>
</resources>
]==]

TEMPLAT.icon = [==[
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="@color/ikon_warna"
        android:pathData="M0,0 L108,0 L108,108 L0,108 Z" />
    <path
        android:fillColor="#FFFFFF"
        android:pathData="M27,27 L81,27 L81,36 L36,36 L36,45 L72,45 L72,54 L36,54 L36,72 L81,72 L81,81 L27,81 Z" />
</vector>
]==]

TEMPLAT.activity = [==[
package @@PAKET@@;

import android.app.Activity;
import android.os.Bundle;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.CookieManager;
import android.view.Window;
import android.graphics.Color;

public class MainActivity extends Activity {
    private WebView web;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);

        web = new WebView(this);
        web.setBackgroundColor(Color.TRANSPARENT);
        setContentView(web);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(@@JS@@);
        s.setDomStorageEnabled(@@SIMPAN@@);
        s.setDatabaseEnabled(@@SIMPAN@@);
        s.setAllowFileAccess(@@FILE_ACCESS@@);
        s.setAllowContentAccess(@@CONTENT_ACCESS@@);
        s.setBuiltInZoomControls(@@ZOOM@@);
        s.setDisplayZoomControls(false);
        s.setSupportZoom(@@ZOOM@@);
        s.setMediaPlaybackRequiresUserGesture(@@MEDIA_GESTURE@@);

        CookieManager.getInstance().setAcceptCookie(true);
        web.setWebViewClient(new WebViewClient());
        web.setWebChromeClient(new WebChromeClient());

        if (savedInstanceState != null) {
            web.restoreState(savedInstanceState);
        } else {
            web.loadUrl("@@ALAMAT@@");
        }
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        if (web != null) web.saveState(outState);
        super.onSaveInstanceState(outState);
    }

    @Override
    public void onBackPressed() {
        if (@@KEMBALI@@ && web != null && web.canGoBack()) {
            web.goBack();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onDestroy() {
        if (web != null) {
            web.loadUrl("about:blank");
            web.stopLoading();
            web.destroy();
        }
        super.onDestroy();
    }
}
]==]

TEMPLAT.nativeJava = [==[
package @@PAKET@@;

import android.app.Activity;
import android.os.Bundle;
import android.graphics.Color;
import android.view.Gravity;
import android.widget.LinearLayout;
import android.widget.TextView;

public class MainActivity extends Activity {
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER);
        box.setPadding(32,32,32,32);
        TextView title = new TextView(this);
        title.setText("@@NAMA_XML@@");
        title.setTextSize(26);
        title.setTextColor(Color.BLACK);
        box.addView(title);
        TextView info = new TextView(this);
        info.setText("Aplikasi Android native siap dikembangkan.");
        box.addView(info);
        setContentView(box);
    }
}
]==]

TEMPLAT.nativeKotlin = [==[
package @@PAKET@@

import android.app.Activity
import android.os.Bundle
import android.graphics.Color
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.TextView

class MainActivity : Activity() {
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val box = LinearLayout(this).apply { orientation=LinearLayout.VERTICAL; gravity=Gravity.CENTER; setPadding(32,32,32,32) }
        box.addView(TextView(this).apply { text="@@NAMA_XML@@"; textSize=26f; setTextColor(Color.BLACK) })
        box.addView(TextView(this).apply { text="Aplikasi Android Kotlin siap dikembangkan." })
        setContentView(box)
    }
}
]==]

TEMPLAT.composeKotlin = [==[
package @@PAKET@@

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier

class MainActivity : ComponentActivity() {
    override fun onCreate(state: Bundle?) { super.onCreate(state); setContent { LayarUtama() } }
}

@Composable fun LayarUtama() {
    Column(Modifier.fillMaxSize(), horizontalAlignment=Alignment.CenterHorizontally, verticalArrangement=Arrangement.Center) {
        Text("@@NAMA_XML@@", style=MaterialTheme.typography.headlineMedium)
        Text("Template Jetpack Compose siap dikembangkan.")
    }
}
]==]

TEMPLAT.serviceJava = [==[
package @@PAKET@@;
import android.app.Service;
import android.content.Intent;
import android.os.IBinder;
public class NovanService extends Service {
    @Override public int onStartCommand(Intent intent,int flags,int startId){ return START_STICKY; }
    @Override public IBinder onBind(Intent intent){ return null; }
}
]==]

TEMPLAT.receiverJava = [==[
package @@PAKET@@;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
public class NovanReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) { }
}
]==]

TEMPLAT.activityTest = [==[
package @@PAKET@@;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.assertTrue;
@RunWith(AndroidJUnit4.class)
public class MainActivityTest { @Test public void aplikasiDapatDiuji(){ assertTrue(true); } }
]==]

TEMPLAT.html = [==[
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="theme-color" content="#@@WARNA_IKON_HEX@@">
<title>@@NAMA_XML@@</title>
<style>
body{font-family:sans-serif;padding:20px;line-height:1.6}
h1{margin-top:0}
.tombol{display:inline-block;padding:12px 16px;border-radius:8px;background:#@@WARNA_IKON_HEX@@;color:#fff;text-decoration:none}
</style>
</head>
<body>
<h1>Halo, dunia!</h1>
<p>Ini halaman awal aplikasi <b>@@NAMA_XML@@</b>.</p>
<p>Anda dapat mengubah halaman ini melalui menu <b>Kelola berkas proyek</b>.</p>
<a class="tombol" href="https://developer.android.com/">Buka Android Developers</a>
</body>
</html>
]==]

TEMPLAT.readme = [==[
# @@NAMA_XML@@

Aplikasi Android yang dibuat melalui Pembuat APK.
Proyek: @@PAKET@@
Versi: @@VERSI@@

APK dibangun otomatis oleh GitHub Actions.
]==]

TEMPLAT.workflowLengkap = [==[
name: Bangun APK Android

on:
  workflow_dispatch:
  push:
    branches: [ main, master ]

permissions:
  contents: write

jobs:
  bangun:
    name: Kompilasi APK
    runs-on: ubuntu-latest
    steps:
      - name: Ambil kode sumber
        uses: actions/checkout@v4

      - name: Pasang Java 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 17

      - name: Siapkan Android SDK
        uses: android-actions/setup-android@v4
        with:
          packages: ''

      - name: Pasang platform Android
        run: |
          sdkmanager --install "platform-tools" "platforms;android-34" "platforms;android-35" "build-tools;34.0.0" "build-tools;35.0.0"
          yes | sdkmanager --licenses >/dev/null || true

      - name: Siapkan Gradle
        uses: gradle/actions/setup-gradle@v4
        with:
          gradle-version: 8.7

      - name: Kompilasi APK Android
        run: gradle assembleDebug --no-daemon -x lint -x test

      - name: Siapkan berkas APK
        run: |
          APK_PATH=$(find app/build/outputs/apk -name "*.apk" | head -n 1)
          test -n "$APK_PATH" || { echo "Berkas APK tidak ditemukan!"; exit 1; }
          cp "$APK_PATH" "@@NAMA_APK@@.apk"

      - name: Simpan Artefak APK
        uses: actions/upload-artifact@v4
        with:
          name: APK-@@NAMA_APK@@-${{ github.run_number }}
          path: "@@NAMA_APK@@.apk"

      - name: Terbitkan ke GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: v${{ github.run_number }}
          name: Versi v${{ github.run_number }}
          generate_release_notes: false
          files: "@@NAMA_APK@@.apk"
]==]

local function isiTemplat(templat, peta)
    return templat:gsub("@@([%u_]+)@@", function(k)
        local v = peta[k]
        if v == nil then return "" end
        return tostring(v)
    end)
end

local function buatSlug(teks)
    local s = tostring(teks):lower()
    s = s:gsub("[^a-z0-9]+", "-")
    s = s:gsub("^%-+", "")
    s = s:gsub("%-+$", "")
    return s
end

local function buatPaketOtomatis(slug)
    local s = slug:gsub("%-", "")
    if s == "" or s:match("^%d") then s = "app" .. s end
    return "com.aplikasi." .. s
end

local function paketValid(paket)
    if paket:find("^%.") or paket:find("%.$") or paket:find("%.%.") then return false end
    local jumlah = 0
    for seg in paket:gmatch("[^%.]+") do
        if not seg:match("^[a-z][a-z0-9_]*$") then return false end
        jumlah = jumlah + 1
    end
    return jumlah >= 2
end

local function escapeXml(s)
    s = tostring(s)
    s = s:gsub("&", "&amp;")
    s = s:gsub("<", "&lt;")
    s = s:gsub(">", "&gt;")
    s = s:gsub('"', "&quot;")
    return s
end

local function escapeJava(s)
    s = tostring(s)
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    return s
end

local function tampilDialog(judul, pesan, pos, net, neg)
    local d = AlertDialog.Builder(service)
    d.setTitle(judul)
    d.setMessage(pesan)
    if pos then
        d.setPositiveButton(pos[1], DialogInterface.OnClickListener{
            onClick = function() if pos[2] then pos[2]() end end
        })
    end
    if net then
        d.setNeutralButton(net[1], DialogInterface.OnClickListener{
            onClick = function() if net[2] then net[2]() end end
        })
    end
    if neg then
        d.setNegativeButton(neg[1], DialogInterface.OnClickListener{
            onClick = function() if neg[2] then neg[2]() end end
        })
    end
    local diag = d.create()
    diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    diag.show()
    aturTombolHurufKecil(diag, pos and pos[1], neg and neg[1], net and net[1])
end

local function ambilDaftarAplikasi()
    local hasil = {}
    pcall(function()
        local arr = JSONArray(prefs.getString(KEY_DAFTAR_APLIKASI, "[]"))
        for i = 0, arr.length() - 1 do table.insert(hasil, arr.getString(i)) end
    end)
    return hasil
end

local function simpanDaftarAplikasi(daftar)
    local arr = JSONArray()
    for _, nama in ipairs(daftar) do arr.put(nama) end
    prefs.edit().putString(KEY_DAFTAR_APLIKASI, arr.toString()).apply()
end

local function tambahKeDaftarAplikasi(fullName)
    local daftar = ambilDaftarAplikasi()
    for _, n in ipairs(daftar) do if n == fullName then return end end
    table.insert(daftar, fullName)
    simpanDaftarAplikasi(daftar)
end

local function terjemahStatus(status, kesimpulan)
    if status == "queued" or status == "waiting" or status == "pending" then
        return "Menunggu giliran"
    elseif status == "in_progress" then
        return "Sedang membangun"
    elseif status == "completed" then
        if kesimpulan == "success" then return "Berhasil"
        elseif kesimpulan == "failure" then return "Gagal"
        elseif kesimpulan == "cancelled" then return "Dibatalkan"
        else return "Selesai (" .. tostring(kesimpulan) .. ")" end
    end
    return tostring(status)
end

local function pilihanTema(n)
    if n == "Gelap" then return "@android:style/Theme.DeviceDefault.NoActionBar"
    elseif n == "Terang" then return "@android:style/Theme.DeviceDefault.Light.NoActionBar"
    else return "@android:style/Theme.DeviceDefault.NoActionBar" end
end

local function pilihanOrientasi(n)
    if n == "Potret" then return "portrait"
    elseif n == "Lanskap" then return "landscape"
    else return "unspecified" end
end

local function buatIzin(o)
    local p = {}
    local function tambah(s) table.insert(p, '    <uses-permission android:name="' .. s .. '" />') end
    if o.internet then tambah("android.permission.INTERNET") end
    if o.statusJaringan then tambah("android.permission.ACCESS_NETWORK_STATE") end
    if o.statusWifi then tambah("android.permission.ACCESS_WIFI_STATE") end
    if o.penyimpanan then
        table.insert(p, '    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />')
        table.insert(p, '    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />')
    end
    if o.kelolaBerkas then tambah("android.permission.MANAGE_EXTERNAL_STORAGE") end
    if o.pasangApk then tambah("android.permission.REQUEST_INSTALL_PACKAGES") end
    if o.audioSetting then tambah("android.permission.MODIFY_AUDIO_SETTINGS") end
    if o.kamera then tambah("android.permission.CAMERA") end
    if o.mikrofon then tambah("android.permission.RECORD_AUDIO") end
    if o.notifikasi then tambah("android.permission.POST_NOTIFICATIONS") end
    if o.lokasi then
        tambah("android.permission.ACCESS_COARSE_LOCATION")
        tambah("android.permission.ACCESS_FINE_LOCATION")
    end
    if o.lokasiLatar then tambah("android.permission.ACCESS_BACKGROUND_LOCATION") end
    if o.bluetooth then
        tambah("android.permission.BLUETOOTH")
        tambah("android.permission.BLUETOOTH_ADMIN")
        tambah("android.permission.BLUETOOTH_CONNECT")
        tambah("android.permission.BLUETOOTH_SCAN")
    end
    if o.bluetoothAdv then tambah("android.permission.BLUETOOTH_ADVERTISE") end
    if o.wifiDekat then tambah("android.permission.NEARBY_WIFI_DEVICES") end
    if o.nfc then tambah("android.permission.NFC") end
    if o.audio then
        if (tonumber(o.targetSdk) or 35) >= 33 then
            tambah("android.permission.READ_MEDIA_AUDIO")
        else
            table.insert(p, '    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />')
        end
    end
    if o.foto then
        if (tonumber(o.targetSdk) or 35) >= 33 then tambah("android.permission.READ_MEDIA_IMAGES") else table.insert(p, '    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />') end
    end
    if o.video then
        if (tonumber(o.targetSdk) or 35) >= 33 then tambah("android.permission.READ_MEDIA_VIDEO") else table.insert(p, '    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />') end
    end
    if o.mediaVisual and (tonumber(o.targetSdk) or 35) >= 34 then tambah("android.permission.READ_MEDIA_VISUAL_USER_SELECTED") end
    if o.kontak then tambah("android.permission.READ_CONTACTS"); tambah("android.permission.WRITE_CONTACTS") end
    if o.kalender then tambah("android.permission.READ_CALENDAR"); tambah("android.permission.WRITE_CALENDAR") end
    if o.telepon then tambah("android.permission.READ_PHONE_STATE") end
    if o.panggilan then tambah("android.permission.CALL_PHONE") end
    if o.sms then tambah("android.permission.READ_SMS"); tambah("android.permission.SEND_SMS") end
    if o.sensorTubuh then tambah("android.permission.BODY_SENSORS") end
    if o.aktivitas then tambah("android.permission.ACTIVITY_RECOGNITION") end
    if o.alarm then tambah("android.permission.SCHEDULE_EXACT_ALARM") end
    if o.boot then tambah("android.permission.RECEIVE_BOOT_COMPLETED") end
    if o.getar then tambah("android.permission.VIBRATE") end
    if o.wake then tambah("android.permission.WAKE_LOCK") end
    if o.overlay then tambah("android.permission.SYSTEM_ALERT_WINDOW") end
    if o.battery then tambah("android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS") end
    if o.fgs or o.fgsMedia or o.fgsCamera or o.fgsMic or o.fgsLocation or o.fgsData or o.fgsDevice or o.fgsMediaProc or o.fgsProjection or o.fgsPhone then
        tambah("android.permission.FOREGROUND_SERVICE")
    end
    if o.fgsMedia then tambah("android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK") end
    if o.fgsCamera then tambah("android.permission.FOREGROUND_SERVICE_CAMERA") end
    if o.fgsMic then tambah("android.permission.FOREGROUND_SERVICE_MICROPHONE") end
    if o.fgsLocation then tambah("android.permission.FOREGROUND_SERVICE_LOCATION") end
    if o.fgsData then tambah("android.permission.FOREGROUND_SERVICE_DATA_SYNC") end
    if o.fgsDevice then tambah("android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE") end
    if o.fgsMediaProc then tambah("android.permission.FOREGROUND_SERVICE_MEDIA_PROCESSING") end
    if o.fgsProjection then tambah("android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION") end
    if o.fgsPhone then tambah("android.permission.FOREGROUND_SERVICE_PHONE_CALL") end
    return table.concat(p, "\n")
end

local function nilaiWorkflowBoolean(v)
    return v and "true" or "false"
end

local function daftarMatrix(jenis)
    if jenis == "debug" then return "debug" end
    if jenis == "release" then return "release" end
    return "debug, release"
end

local function jenisProyekNormal(o)
    local x = tostring(o.jenisProyek or "webview")
    if x=="java" or x=="kotlin" or x=="compose" or x=="webview" or x=="html" then return x end
    return "webview"
end

local function dependencyTambahan(o)
    local d={}
    local function add(x) table.insert(d,x) end
    if o.camerax then add("implementation 'androidx.camera:camera-core:1.3.4'"); add("implementation 'androidx.camera:camera-camera2:1.3.4'"); add("implementation 'androidx.camera:camera-lifecycle:1.3.4'"); add("implementation 'androidx.camera:camera-view:1.3.4'") end
    if o.mlkit then add("implementation 'com.google.mlkit:text-recognition:16.0.1'") end
    if o.room then add("implementation 'androidx.room:room-runtime:2.6.1'"); add((o.kotlin and "kapt 'androidx.room:room-compiler:2.6.1'") or "annotationProcessor 'androidx.room:room-compiler:2.6.1'") end
    if o.recyclerview then add("implementation 'androidx.recyclerview:recyclerview:1.3.2'") end
    if o.constraint then add("implementation 'androidx.constraintlayout:constraintlayout:2.1.4'") end
    if o.lifecycle then add("implementation 'androidx.lifecycle:lifecycle-runtime:2.8.4'") end
    if o.navigation then add("implementation 'androidx.navigation:navigation-fragment:2.7.7'"); add("implementation 'androidx.navigation:navigation-ui:2.7.7'") end
    if o.compose then
        add("implementation platform('androidx.compose:compose-bom:2024.06.00')")
        add("implementation 'androidx.activity:activity-compose:1.9.1'")
        add("implementation 'androidx.compose.ui:ui'")
        add("implementation 'androidx.compose.ui:ui-tooling-preview'")
        add("implementation 'androidx.compose.material3:material3'")
        add("debugImplementation 'androidx.compose.ui:ui-tooling'")
    end
    add("implementation fileTree(dir: 'libs', include: ['*.jar','*.aar'])")
    return table.concat(d,"\n    ")
end

PembuatAPK.susunBerkas = function(o)
    local proyek = jenisProyekNormal(o)
    local alamat = (o.url ~= "") and o.url or "file:///android_asset/index.html"
    local versiBersih = tostring(o.versi):gsub("[^%w%.%-]", "")
    if versiBersih == "" then versiBersih = "1.0.0" end
    local javaVersion = o.javaVersion or "17"
    local gradleVersion = o.gradleVersion or "8.7"
    local jenis = o.jenisBuild or "debug"
    local matrixJenis = daftarMatrix(jenis)
    local apk = o.hasApk ~= false
    local aab = o.hasAab == true

    local triggerPush = o.push and "  push:\n    branches: [ main, master ]" or ""
    local triggerPr = o.pullRequest and "  pull_request:" or ""
    local triggerSchedule = o.schedule and "  schedule:\n    - cron: '0 0 * * 0'" or ""

    local peta = {
        NAMA_PROYEK=o.slug, NAMA_APK=o.slug, NAMA_XML=escapeXml(o.nama), PAKET=o.paket,
        VERSI=versiBersih, VERSION_CODE=o.versionCode, COMPILE_SDK=o.compileSdk,
        MIN_SDK=o.minSdk, TARGET_SDK=o.targetSdk, ALAMAT=escapeJava(alamat),
        JS=nilaiWorkflowBoolean(o.js), SIMPAN=nilaiWorkflowBoolean(o.simpan),
        FILE_ACCESS=nilaiWorkflowBoolean(o.fileAccess), CONTENT_ACCESS=nilaiWorkflowBoolean(o.contentAccess),
        ZOOM=nilaiWorkflowBoolean(o.zoom), MEDIA_GESTURE=nilaiWorkflowBoolean(not o.mediaGesture),
        KEMBALI=nilaiWorkflowBoolean(o.kembali), IZIN=buatIzin(o), BACKUP=nilaiWorkflowBoolean(o.backup),
        CLEAR_TEXT=nilaiWorkflowBoolean(o.clearText), TEMA=pilihanTema(o.tema), ORIENTASI=pilihanOrientasi(o.orientasi),
        WARNA_IKON=o.warnaIkon, WARNA_IKON_HEX=o.warnaIkon:gsub("#",""),
        COMPONENTS=(o.service and '        <service android:name=".NovanService" android:exported="false" />\n' or '') .. (o.receiver and '        <receiver android:name=".NovanReceiver" android:exported="false" />' or ''),
        JAVA_VERSION=javaVersion, GRADLE_VERSION=gradleVersion, COMPILE_SDK=o.compileSdk,
        KOTLIN_PLUGIN=(proyek=="kotlin" or proyek=="compose") and ((o.room and "id 'org.jetbrains.kotlin.android'\n     id 'org.jetbrains.kotlin.kapt'") or "id 'org.jetbrains.kotlin.android'") or "",
        KOTLIN_OPTIONS=(proyek=="kotlin" or proyek=="compose") and "kotlinOptions { jvmTarget = '17' }" or "",
        COMPOSE_ENABLED=nilaiWorkflowBoolean(proyek=="compose"),
        COMPOSE_OPTIONS=(proyek=="compose") and "composeOptions { kotlinCompilerExtensionVersion '1.5.14' }" or "",
        DEPENDENCIES=dependencyTambahan({camerax=o.camerax,mlkit=o.mlkit,room=o.room,kotlin=(proyek=="kotlin" or proyek=="compose"),recyclerview=o.recyclerview,constraint=o.constraint,lifecycle=o.lifecycle,navigation=o.navigation,compose=(proyek=="compose")}),
        TRIGGER_PUSH=triggerPush, TRIGGER_PR=triggerPr, TRIGGER_SCHEDULE=triggerSchedule,
        VALIDATE_WRAPPER=nilaiWorkflowBoolean(o.validateWrapper), RUN_LINT=nilaiWorkflowBoolean(o.runLint),
        RUN_UNIT_TEST=nilaiWorkflowBoolean(o.runUnitTest), RUN_INSTRUMENTATION=nilaiWorkflowBoolean(o.runInstrumentation),
        HAS_APK=nilaiWorkflowBoolean(apk), HAS_AAB=nilaiWorkflowBoolean(aab), SIGNING=nilaiWorkflowBoolean(o.signing),
        MINIFY=nilaiWorkflowBoolean(o.minify), SHRINK=nilaiWorkflowBoolean(o.shrink),
        CACHE_DISABLED=nilaiWorkflowBoolean(not o.cache),
        MATRIX_JENIS=matrixJenis, FAIL_FAST=nilaiWorkflowBoolean(o.failFast),
        ABI_SPLIT=nilaiWorkflowBoolean(o.abi and o.abi ~= "universal"),
        ABI_INCLUDE=(o.abi == "arm64" and "'arm64-v8a'" or o.abi == "armv7" and "'armeabi-v7a'" or o.abi == "arm64armv7" and "'arm64-v8a', 'armeabi-v7a'" or "'arm64-v8a', 'armeabi-v7a'"),
        RETENTION=o.retention or 30, PUBLISH_RELEASE=nilaiWorkflowBoolean(o.publish),
        MAKE_RELEASE=nilaiWorkflowBoolean(o.makeRelease), NAMA_RELEASE=escapeJava(o.nama),
        ATTEST=nilaiWorkflowBoolean(o.attest), EMULATOR_API=o.emulatorApi or 30,
    }

    local berkas={
        {path="settings.gradle",isi=isiTemplat(TEMPLAT.settings,peta)},
        {path="build.gradle",isi=isiTemplat(TEMPLAT.buildRoot,peta)},
        {path="gradle.properties",isi=isiTemplat(TEMPLAT.gradleProps,peta)},
        {path="app/build.gradle",isi=isiTemplat(TEMPLAT.buildApp,peta)},
        {path="app/proguard-rules.pro",isi=TEMPLAT.proguard},
        {path="app/src/main/AndroidManifest.xml",isi=isiTemplat(TEMPLAT.manifest,peta)},
        {path="app/src/main/res/values/strings.xml",isi=isiTemplat(TEMPLAT.strings,peta)},
        {path="app/src/main/res/drawable/ikon_aplikasi.xml",isi=isiTemplat(TEMPLAT.icon,peta)},
        {path="app/src/main/java/"..o.paket:gsub("%.","/").."/MainActivity.java",isi=isiTemplat(((proyek=="webview" or proyek=="html") and TEMPLAT.activity or TEMPLAT.nativeJava),peta)},
        {path=".github/workflows/"..NAMA_ALUR_KERJA,isi=isiTemplat(TEMPLAT.workflowLengkap,peta)},
    }
    if o.readme then
        berkas[#berkas+1]={path="README.md",isi=isiTemplat(TEMPLAT.readme,peta)}
    end
    if proyek=="kotlin" or proyek=="compose" then
        table.remove(berkas,9)
        berkas[#berkas+1]={path="app/src/main/java/"..o.paket:gsub("%.","/").."/MainActivity.kt",isi=isiTemplat(proyek=="compose" and TEMPLAT.composeKotlin or TEMPLAT.nativeKotlin,peta)}
    end
    if o.service then berkas[#berkas+1]={path="app/src/main/java/"..o.paket:gsub("%.","/").."/NovanService.java",isi=isiTemplat(TEMPLAT.serviceJava,peta)} end
    if o.receiver then berkas[#berkas+1]={path="app/src/main/java/"..o.paket:gsub("%.","/").."/NovanReceiver.java",isi=isiTemplat(TEMPLAT.receiverJava,peta)} end
    if o.instrumentationTest then berkas[#berkas+1]={path="app/src/androidTest/java/"..o.paket:gsub("%.","/").."/MainActivityTest.java",isi=isiTemplat(TEMPLAT.activityTest,peta)} end
    berkas[#berkas+1]={path="app/libs/README.txt",isi="Letakkan file .jar atau .aar lokal di folder libs.\nLibrary native .so dapat ditempatkan sesuai ABI di src/main/jniLibs/."}
    if (proyek=="webview" or proyek=="html") and o.url == "" then
        local html=o.html
        if html=="" then html=isiTemplat(TEMPLAT.html,peta) end
        table.insert(berkas,{path="app/src/main/assets/index.html",isi=html})
    end
    return berkas
end

function PembuatAPK.unggahBerurutan(fullName, token, berkas, idx, progress, onSelesai)
    if idx > #berkas then onSelesai(true, ""); return end
    local b = berkas[idx]
    pcall(function()
        progress.setMessage("Mengunggah berkas " .. idx .. " dari " .. #berkas .. ":\n" .. b.path)
    end)
    local payload = JSONObject()
    payload.put("message", "Tambah " .. b.path)
    payload.put("content", Base64.encodeToString(String(b.isi).getBytes("UTF-8"), Base64.NO_WRAP))
    local endpoint = "https://api.github.com/repos/" .. fullName .. "/contents/" .. b.path
    kirimPermintaanGitHub("PUT", endpoint, token, payload.toString(), function(ok, res)
        if ok then
            PembuatAPK.unggahBerurutan(fullName, token, berkas, idx + 1, progress, onSelesai)
        else
            onSelesai(false, "Gagal mengunggah " .. b.path .. ":\n" .. tostring(res))
        end
    end, true)
end

function PembuatAPK.buatProyek(token, o)
    local berkas = PembuatAPK.susunBerkas(o)
    local progress = ProgressDialog(service)
    progress.setTitle("Membuat proyek aplikasi")
    progress.setMessage("Membuat repositori proyek...")
    progress.setCancelable(false)
    progress.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    progress.show()

    local body = JSONObject()
    body.put("name", o.slug)
    body.put("description", "Proyek aplikasi " .. o.nama .. " dibuat dari Pembuat APK")
    body.put("private", o.privat)
    body.put("auto_init", false)

    kirimPermintaanGitHub("POST", "https://api.github.com/user/repos", token, body.toString(), function(ok, res)
        if not ok then
            pcall(function() progress.dismiss() end)
            tampilDialog("Gagal membuat proyek", tostring(res),
                {"coba lagi", function() PembuatAPK.formAplikasiBaru(token) end}, nil,
                {"kembali", function() PembuatAPK.menu(token) end})
            return
        end

        local repo = JSONObject(res)
        local fullName = repo.optString("full_name", "")
        local htmlUrl = repo.optString("html_url", "")
        pcall(function() progress.setMessage("Repositori dibuat. Mengunggah " .. #berkas .. " berkas konfigurasi...") end)

        PembuatAPK.unggahBerurutan(fullName, token, berkas, 1, progress, function(sukses, pesanGagal)
            pcall(function() progress.dismiss() end)
            if not sukses then
                local pesan = pesanGagal
                if pesan:lower():find("workflow") then
                    pesan = pesan .. "\n\nToken GitHub perlu izin workflow."
                end
                tampilDialog("Pembuatan terhenti", pesan .. "\n\nRepositori sudah dibuat di:\n" .. htmlUrl,
                    {"buka di GitHub", function() bukaBrowser(htmlUrl) end}, nil,
                    {"kembali", function() PembuatAPK.menu(token) end})
                return
            end

            tambahKeDaftarAplikasi(fullName)
            if service.speak then service.speak("Proyek aplikasi berhasil dibuat.") end
            local info = "Proyek aplikasi berhasil dibuat.\n\nRepositori: " .. fullName
            if o.otomatis then
                info = info .. "\n\nPembangunan otomatis akan dimulai saat perubahan masuk ke cabang utama."
            else
                info = info .. "\n\nPilih Mulai pembangunan APK jika ingin membangun sekarang."
            end
            tampilDialog("Proyek berhasil dibuat", info,
                {"mulai pembangunan", function() PembuatAPK.bangunUlang(fullName, token) end},
                {"cek status", function() PembuatAPK.cekStatus(fullName, token) end},
                {"kembali", function() PembuatAPK.menu(token) end})
        end)
    end)
end

PembuatAPK.formAplikasiBaru = function(token)
    local root=LinearLayout(service); root.setOrientation(LinearLayout.VERTICAL); root.setPadding(40,20,40,10)
    local function lab(t)
        local v=TextView(service); v.setText(t); v.setPadding(0,14,0,4); root.addView(v)
    end
    local function inp(h,def,multi)
        local e=EditText(service); e.setHint(h); if def then e.setText(def) end; if not multi then e.setSingleLine(true) end; root.addView(e); return e
    end
    local function chk(t,v)
        local c=CheckBox(service); c.setText(t); c.setChecked(v); root.addView(c); return c
    end
    local function spin(t,items,idx)
        lab(t); local s=Spinner(service); local a=ArrayAdapter(service,android.R.layout.simple_spinner_item,items); a.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item); s.setAdapter(a); s.setSelection(idx or 0); root.addView(s); return s
    end
    local function sv(s) return tostring(s.getSelectedItem()) end

    lab("IDENTITAS APLIKASI")
    local nama=inp("Nama aplikasi, contoh: Toko Saya")
    local paket=inp("Nama paket, contoh: com.toko.saya")
    local versi=inp("Versi aplikasi, misalnya 1.0.0")
    local vc=inp("Nomor versi internal, misalnya 1")

    lab("SUMBER APLIKASI")
    local url=inp("Alamat situs https://...")
    local html=inp("HTML halaman awal jika alamat situs kosong",nil,true); html.setMinLines(4)

    lab("JENIS PROYEK")
    local proyek=spin("Jenis aplikasi",{"Situs web (WebView)","Halaman HTML","Aplikasi Android (Java)","Aplikasi Android (Kotlin)","Aplikasi Android modern (Compose)"},0)
    lab("FITUR TAMBAHAN")
    local chkService=chk("Jalankan aplikasi di latar belakang",false); local receiver=chk("Menerima perintah dari sistem",false)
    local cameraX=chk("Kamera modern (CameraX)",false); local mlkit=chk("Membaca teks dari gambar (ML Kit)",false)
    local room=chk("Database lokal (Room)",false); local recycler=chk("Daftar yang ringan (RecyclerView)",false)
    local constraint=chk("Tata letak fleksibel (ConstraintLayout)",false); local lifecycle=chk("Kelola siklus aplikasi",false)
    local navigation=chk("Navigasi antarhalaman",false)

    lab("PENGATURAN ANDROID")
    local minSdk=inp("Versi Android minimum, misalnya 21"); local targetSdk=inp("Versi Android target, misalnya 35"); local compileSdk=inp("Versi Android untuk kompilasi, misalnya 35")
    local tema=spin("Mode tampilan",{"Gelap","Terang"},1)
    local orientasi=spin("Posisi layar",{"Otomatis","Potret","Lanskap"},0)
    local warna=inp("Warna ikon, misalnya #1976D2")

    lab("PENGATURAN SITUS WEB")
    local js=chk("Aktifkan JavaScript",true); local simpan=chk("Simpan cookie, data situs, dan login",true)
    local fa=chk("Izinkan akses berkas",true); local ca=chk("Izinkan akses konten",true)
    local zoom=chk("Aktifkan pembesaran",false); local media=chk("Media boleh diputar tanpa sentuhan",false); local back=chk("Tombol kembali membuka halaman sebelumnya",true)

    lab("IZIN APLIKASI")
    local internet=chk("Akses internet",true)
    local statusJaringan=chk("Status jaringan (Network State)",true)
    local statusWifi=chk("Status Wi-Fi (Wi-Fi State)",false)
    local penyimpanan=chk("Penyimpanan / Unduh berkas (Storage)",false)
    local kelolaBerkas=chk("Kelola semua berkas (Manage Storage)",false)
    local pasangApk=chk("Pasang paket APK (Request Install)",false)
    local audioSetting=chk("Pengaturan audio perangkat",false)
    local audio=chk("Membaca musik dan audio",false); local foto=chk("Membaca foto",false); local video=chk("Membaca video",false); local mediaVisual=chk("Memilih foto atau video",false)
    local kamera=chk("Kamera",false); local mikro=chk("Mikrofon dan rekam suara",false); local notif=chk("Notifikasi",false); local lokasi=chk("Lokasi",false); local lokasiLatar=chk("Lokasi saat aplikasi di latar",false)
    local bluetooth=chk("Bluetooth",false); local bluetoothAdv=chk("Bluetooth: mengiklankan perangkat",false); local wifiDekat=chk("Perangkat Wi-Fi di sekitar",false); local nfc=chk("NFC",false); local usb=chk("Perangkat USB",false)
    local kontak=chk("Kontak",false); local kalender=chk("Kalender",false); local telepon=chk("Informasi telepon",false); local panggilan=chk("Melakukan panggilan telepon",false); local sms=chk("SMS",false); local sensorTubuh=chk("Sensor tubuh",false); local aktivitas=chk("Aktivitas fisik",false)
    local alarm=chk("Alarm tepat waktu",false); local boot=chk("Jalankan setelah HP menyala",false); local getar=chk("Getar",false); local wake=chk("Menjaga aplikasi tetap aktif",false); local overlay=chk("Tampil di atas aplikasi lain",false); local battery=chk("Abaikan penghemat baterai",false)
    local fgs=chk("Layanan latar depan",false); local fgsMedia=chk("Layanan latar depan: memutar musik",false); local fgsCamera=chk("Layanan latar depan: kamera",false); local fgsMic=chk("Layanan latar depan: mikrofon",false); local fgsLocation=chk("Layanan latar depan: lokasi",false); local fgsData=chk("Layanan latar depan: sinkronisasi data",false); local fgsDevice=chk("Layanan latar depan: perangkat terhubung",false); local fgsMediaProc=chk("Layanan latar depan: pemrosesan media",false); local fgsProjection=chk("Layanan latar depan: tangkap layar",false); local fgsPhone=chk("Layanan latar depan: telepon",false)

    lab("HASIL PEMBUATAN")
    local jenis=spin("Jenis pembuatan",{"Uji coba saja (Debug)","Versi rilis saja (Release)","Uji coba + versi rilis"},0)
    local hasil=spin("Berkas hasil",{"APK untuk dipasang di HP","AAB untuk Play Store","APK + AAB"},0)
    local abi=spin("Jenis prosesor HP",{"Semua / Universal","ARM64-v8a","ARMv7","ARM64 + ARMv7"},0)
    local minify=chk("Optimasi R8/Minify saat Release",false); local shrink=chk("Hapus resource yang tidak dipakai",false)

    lab("PEMERIKSAAN DAN UJI APLIKASI")
    local lint=chk("Periksa kesalahan kode",true); local unit=chk("Jalankan tes kode",false); local instr=chk("Tes di HP Android virtual",false)
    local wrapper=chk("Periksa alat Gradle",false); local failfast=chk("Hentikan semua pembangunan jika ada yang gagal",true)
    local emulator=spin("Versi Android emulator",{"30","31","32","33","34","35"},0)

    lab("PEMBANGUNAN OTOMATIS GITHUB")
    local push=chk("Bangun otomatis saat kode dikirim ke main/master",false); local pr=chk("Bangun otomatis saat ada Pull Request",false); local schedule=chk("Bangun otomatis setiap minggu",false)
    local cache=chk("Percepat pembangunan dengan cache",true); local publish=chk("Siapkan hasil untuk dipublikasikan",true); local release=chk("Buat rilis GitHub otomatis",true)
    local attest=chk("Buat bukti asal hasil pembangunan",false)
    local retention=inp("Lama simpan hasil build dalam hari, misalnya 30")

    lab("TANDA TANGAN VERSI RILIS")
    local signing=chk("Tanda tangani versi rilis dengan GitHub Secrets",false)
    local readme=chk("Buat petunjuk aplikasi (README)",true)
    lab("Jika signing diaktifkan, buat Secrets berikut di GitHub: KEYSTORE_BASE64, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD. Password tidak ditulis ke dalam source code.")

    local scroll=ScrollView(service.getApplicationContext()); scroll.setFillViewport(true); scroll.addView(root)
    local b=AlertDialog.Builder(service); b.setTitle("Buat APK Android lengkap"); b.setView(scroll)
    b.setPositiveButton("buat proyek",DialogInterface.OnClickListener{onClick=function()
        local function val(e) return tostring(e.getText()):match("^%s*(.-)%s*$") end
        local function laporErrorForm(pesan)
            if service.speak then service.speak("Periksa isian: " .. pesan) end
            local bErr = AlertDialog.Builder(service)
            bErr.setTitle("Isian Belum Tepat")
            bErr.setMessage(pesan)
            bErr.setPositiveButton("perbaiki", nil)
            local dErr = bErr.create()
            dErr.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
            dErr.show()
            aturTombolHurufKecil(dErr, "perbaiki", nil, nil)
        end

        local n = val(nama)
        if n == "" then
            laporErrorForm("Nama aplikasi wajib diisi.")
            return
        end

        local slug = buatSlug(n)
        if slug == "" then
            laporErrorForm("Nama aplikasi harus mengandung huruf atau angka.")
            return
        end

        local pk = val(paket)
        if pk == "" then pk = buatPaketOtomatis(slug) end
        if not paketValid(pk) then
            laporErrorForm("Nama paket tidak valid. Format harus huruf kecil tanpa spasi dengan titik, contoh: com.musik.saya")
            return
        end

        local mi = tonumber(val(minSdk)) or 24
        local ta = tonumber(val(targetSdk)) or 35
        local co = tonumber(val(compileSdk)) or 35
        local vcode = tonumber(val(vc)) or 1
        local vv = val(versi)
        if vv == "" then vv = "1.0.0" end

        if mi < 21 or mi > 35 then
            laporErrorForm("Versi Android minimum harus antara 21 sampai 35.")
            return
        end
        if ta < mi or ta > 35 then
            laporErrorForm("Versi Android target harus minimal sama dengan versi minimum dan maksimal 35.")
            return
        end
        if co < ta or co > 35 then
            laporErrorForm("Versi Android kompilasi harus minimal sama dengan versi target dan maksimal 35.")
            return
        end
        if vcode < 1 then
            laporErrorForm("Nomor versi internal harus bilangan bulat minimal 1.")
            return
        end

        local w = val(warna)
        if w == "" then w = "#1976D2" end
        if not w:match("^#%x%x%x%x%x%x$") then
            laporErrorForm("Warna ikon harus format tanda pagar diikuti 6 digit heksadesimal, contoh: #1976D2")
            return
        end

        local lamaSimpan = tonumber(val(retention)) or 30
        if lamaSimpan < 1 or lamaSimpan > 90 then
            laporErrorForm("Lama simpan hasil build harus antara 1 sampai 90 hari.")
            return
        end
        local pj=sv(proyek); local jenisProyek=(pj=="Aplikasi Android (Java)" and "java" or pj=="Aplikasi Android (Kotlin)" and "kotlin" or pj=="Aplikasi Android modern (Compose)" and "compose" or pj=="Halaman HTML" and "html" or "webview")
        local j=sv(jenis); local jenisBuild=(j:find("Uji coba %+ versi rilis") and "both") or (j:find("Versi rilis") and "release" or "debug")
        local h=sv(hasil); local hasApk=h=="APK" or h=="APK + AAB"; local hasAab=h=="AAB" or h=="APK + AAB"
        local apiEmulator=tonumber(sv(emulator)) or 30
        if instr.isChecked() and apiEmulator < mi then Toast.makeText(service,"Versi Android emulator harus sama atau lebih tinggi dari Versi Android minimum.",Toast.LENGTH_LONG).show(); return end
        PembuatAPK.buatProyek(token,{nama=n,slug=slug,paket=pk,versi=vv,versionCode=vcode,minSdk=mi,targetSdk=ta,compileSdk=co,url=val(url),html=tostring(html.getText()),jenisProyek=jenisProyek,service=chkService.isChecked(),receiver=receiver.isChecked(),camerax=cameraX.isChecked(),mlkit=mlkit.isChecked(),room=room.isChecked(),recyclerview=recycler.isChecked(),constraint=constraint.isChecked(),lifecycle=lifecycle.isChecked(),navigation=navigation.isChecked(),instrumentationTest=instr.isChecked(),
            js=js.isChecked(),simpan=simpan.isChecked(),fileAccess=fa.isChecked(),contentAccess=ca.isChecked(),zoom=zoom.isChecked(),mediaGesture=media.isChecked(),kembali=back.isChecked(),
            internet=internet.isChecked(),statusJaringan=statusJaringan.isChecked(),statusWifi=statusWifi.isChecked(),penyimpanan=penyimpanan.isChecked(),kelolaBerkas=kelolaBerkas.isChecked(),pasangApk=pasangApk.isChecked(),audioSetting=audioSetting.isChecked(),audio=audio.isChecked(),foto=foto.isChecked(),video=video.isChecked(),mediaVisual=mediaVisual.isChecked(),kamera=kamera.isChecked(),mikrofon=mikro.isChecked(),notifikasi=notif.isChecked(),lokasi=lokasi.isChecked(),lokasiLatar=lokasiLatar.isChecked(),bluetooth=bluetooth.isChecked(),bluetoothAdv=bluetoothAdv.isChecked(),wifiDekat=wifiDekat.isChecked(),nfc=nfc.isChecked(),usb=usb.isChecked(),kontak=kontak.isChecked(),kalender=kalender.isChecked(),telepon=telepon.isChecked(),panggilan=panggilan.isChecked(),sms=sms.isChecked(),sensorTubuh=sensorTubuh.isChecked(),aktivitas=aktivitas.isChecked(),alarm=alarm.isChecked(),boot=boot.isChecked(),getar=getar.isChecked(),wake=wake.isChecked(),overlay=overlay.isChecked(),battery=battery.isChecked(),fgs=fgs.isChecked(),fgsMedia=fgsMedia.isChecked(),fgsCamera=fgsCamera.isChecked(),fgsMic=fgsMic.isChecked(),fgsLocation=fgsLocation.isChecked(),fgsData=fgsData.isChecked(),fgsDevice=fgsDevice.isChecked(),fgsMediaProc=fgsMediaProc.isChecked(),fgsProjection=fgsProjection.isChecked(),fgsPhone=fgsPhone.isChecked(),
            jenisBuild=jenisBuild,hasApk=hasApk,hasAab=hasAab,abi=(sv(abi)=="ARM64-v8a" and "arm64" or sv(abi)=="ARMv7" and "armv7" or sv(abi)=="ARM64 + ARMv7" and "arm64armv7" or "universal"),minify=minify.isChecked(),shrink=shrink.isChecked(),runLint=lint.isChecked(),runUnitTest=unit.isChecked(),runInstrumentation=instr.isChecked(),
            validateWrapper=wrapper.isChecked(),failFast=failfast.isChecked(),emulatorApi=apiEmulator,push=push.isChecked(),pullRequest=pr.isChecked(),schedule=schedule.isChecked(),cache=cache.isChecked(),
            publish=publish.isChecked(),makeRelease=release.isChecked(),attest=attest.isChecked(),retention=lamaSimpan,signing=signing.isChecked(),readme=readme.isChecked(),tema=sv(tema),orientasi=sv(orientasi),warnaIkon=w,backup=true,clearText=false,
            javaVersion="17",gradleVersion="8.7",mediaGesture=media.isChecked()})
    end})
    b.setNegativeButton("kembali",DialogInterface.OnClickListener{onClick=function() PembuatAPK.menu(token) end})
    local d=b.create(); d.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY); d.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE); d.show(); aturTombolHurufKecil(d,"buat proyek","kembali",nil)
end

function PembuatAPK.bacaLogError(fullName, token, runId, logUrl)
    local progress = ProgressDialog(service)
    progress.setTitle("Menganalisis Error")
    progress.setMessage("Mengambil rincian kegagalan build...")
    progress.setCancelable(true)
    progress.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    progress.show()

    local endpointJobs = "https://api.github.com/repos/" .. fullName .. "/actions/runs/" .. tostring(runId) .. "/jobs"
    kirimPermintaanGitHub("GET", endpointJobs, token, nil, function(okJobs, resJobs)
        if not okJobs then
            pcall(function() progress.dismiss() end)
            Toast.makeText(service, "Gagal memeriksa status job: " .. tostring(resJobs), Toast.LENGTH_LONG).show()
            return
        end

        local targetJobId = nil
        local namaLangkahGagal = "Tidak diketahui"

        pcall(function()
            local jobsArr = JSONObject(resJobs).optJSONArray("jobs")
            if jobsArr ~= nil then
                for i = 0, jobsArr.length() - 1 do
                    local j = jobsArr.getJSONObject(i)
                    if j.optString("conclusion", "") == "failure" then
                        targetJobId = j.optLong("id", 0)
                        local stepsArr = j.optJSONArray("steps")
                        if stepsArr ~= nil then
                            for k = 0, stepsArr.length() - 1 do
                                local st = stepsArr.getJSONObject(k)
                                if st.optString("conclusion", "") == "failure" then
                                    namaLangkahGagal = st.optString("name", "Kompilasi")
                                    break
                                end
                            end
                        end
                        break
                    end
                end
            end
        end)

        if not targetJobId or targetJobId == 0 then
            pcall(function() progress.dismiss() end)
            tampilDialog("Rincian Error", "Tidak ditemukan rincian langkah gagal pada pembangunan ini.",
                {"buka log di web", function() bukaBrowser(logUrl) end}, nil,
                {"kembali", function() PembuatAPK.cekStatus(fullName, token) end})
            return
        end

        pcall(function() progress.setMessage("Mengunduh teks log dari GitHub...") end)

        Thread(Runnable{
            run = function()
                local okLog, hasilLog = pcall(function()
                    local urlStr = "https://api.github.com/repos/" .. fullName .. "/actions/jobs/" .. tostring(targetJobId) .. "/logs"
                    local url = URL(urlStr)
                    local conn = url.openConnection()
                    conn.setRequestMethod("GET")
                    conn.setRequestProperty("Authorization", "Bearer " .. token)
                    conn.setRequestProperty("User-Agent", "Android-Accessibility-Manager")
                    conn.setConnectTimeout(15000)
                    conn.setReadTimeout(30000)

                    local code = conn.getResponseCode()
                    if code == 301 or code == 302 or code == 307 then
                        local redir = conn.getHeaderField("Location")
                        conn.disconnect()
                        url = URL(redir)
                        conn = url.openConnection()
                        conn.setRequestMethod("GET")
                        conn.setRequestProperty("User-Agent", "Android-Accessibility-Manager")
                        conn.setConnectTimeout(15000)
                        conn.setReadTimeout(30000)
                    end

                    local is = conn.getInputStream()
                    local reader = BufferedReader(InputStreamReader(is, "UTF-8"))
                    local barisLog = {}
                    local l = reader.readLine()
                    while l ~= nil do
                        table.insert(barisLog, tostring(l))
                        if #barisLog > 2000 then table.remove(barisLog, 1) end
                        l = reader.readLine()
                    end
                    reader.close()
                    is.close()
                    conn.disconnect()
                    return barisLog
                end)

                mainHandler.post(Runnable{
                    run = function()
                        pcall(function() progress.dismiss() end)
                        if not okLog or not hasilLog or #hasilLog == 0 then
                            tampilDialog("Gagal Mengambil Log", "Tidak dapat membaca berkas log: " .. tostring(hasilLog),
                                {"buka log di web", function() bukaBrowser(logUrl) end}, nil,
                                {"kembali", function() PembuatAPK.cekStatus(fullName, token) end})
                            return
                        end

                        local ringkasanError = {}
                        local barisKandidat = {}

                        for idx, baris in ipairs(hasilLog) do
                            local clean = baris:gsub("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d%.%d+Z%s*", "")
                            local lower = clean:lower()
                            if lower:find("error:") or lower:find("failure:") or lower:find("failed") or lower:find("%* what went wrong") or lower:find("cannot find symbol") then
                                table.insert(barisKandidat, clean)
                            end
                        end

                        if #barisKandidat > 0 then
                            local startIdx = math.max(1, #barisKandidat - 20)
                            for i = startIdx, #barisKandidat do
                                table.insert(ringkasanError, barisKandidat[i])
                            end
                        else
                            local startIdx = math.max(1, #hasilLog - 25)
                            for i = startIdx, #hasilLog do
                                local clean = hasilLog[i]:gsub("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d%.%d+Z%s*", "")
                                table.insert(ringkasanError, clean)
                            end
                        end

                        local teksGabungan = "Langkah gagal: " .. namaLangkahGagal .. "\n\n--- Rincian Error ---\n" .. table.concat(ringkasanError, "\n")

                        local layout = LinearLayout(service)
                        layout.setOrientation(LinearLayout.VERTICAL)
                        layout.setPadding(32, 16, 32, 16)

                        local tv = TextView(service)
                        tv.setText(teksGabungan)
                        tv.setTextSize(13)
                        tv.setTextIsSelectable(true)
                        layout.addView(tv)

                        local scroll = ScrollView(service.getApplicationContext())
                        scroll.setFillViewport(true)
                        scroll.addView(layout)

                        if service.speak then service.speak("Langkah gagal: " .. namaLangkahGagal .. ". Rincian error ditampilkan.") end

                        local dErr = AlertDialog.Builder(service)
                        dErr.setTitle("Hasil Analisis Error APK")
                        dErr.setView(scroll)
                        dErr.setPositiveButton("salin error", DialogInterface.OnClickListener{
                            onClick = function() salinKeClipboard("Log Error APK", teksGabungan) end
                        })
                        dErr.setNeutralButton("buka di web", DialogInterface.OnClickListener{
                            onClick = function() bukaBrowser(logUrl) end
                        })
                        dErr.setNegativeButton("kembali", DialogInterface.OnClickListener{
                            onClick = function() PembuatAPK.cekStatus(fullName, token) end
                        })
                        local diag = dErr.create()
                        diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                        diag.show()
                        aturTombolHurufKecil(diag, "salin error", "kembali", "buka di web")
                    end
                })
            end
        }).start()
    end, true)
end

function PembuatAPK.cekStatus(fullName, token)
    local endpoint="https://api.github.com/repos/"..fullName.."/actions/runs?per_page=1"
    kirimPermintaanGitHub("GET",endpoint,token,nil,function(ok,res)
        if not ok then
            Toast.makeText(service,"Gagal memeriksa status: "..tostring(res),Toast.LENGTH_LONG).show()
            return
        end
        local arr=JSONObject(res).optJSONArray("workflow_runs")
        if arr==nil or arr.length()==0 then
            tampilDialog("Status pembangunan","Belum ada pembangunan APK yang tercatat.",
                {"mulai pembangunan",function() PembuatAPK.bangunUlang(fullName,token) end},nil,
                {"kembali",function() PembuatAPK.menuAplikasi(fullName,token) end})
            return
        end
        local run=arr.getJSONObject(0)
        local status=run.optString("status","")
        local kesimpulan=run.optString("conclusion","")
        local teksStatus=terjemahStatus(status,kesimpulan)
        local pesan="Proyek: "..fullName.."\nStatus: "..teksStatus
        if status=="completed" and kesimpulan=="success" then
            pesan=pesan.."\n\nAPK sudah selesai dan dapat diunduh."
            tampilDialog("Pembangunan selesai",pesan,
                {"unduh APK",function() PembuatAPK.ambilAPK(fullName,token) end},
                {"cek lagi",function() PembuatAPK.cekStatus(fullName,token) end},
                {"kembali",function() PembuatAPK.menuAplikasi(fullName,token) end})
        elseif status=="completed" then
            pesan=pesan.."\n\nPembangunan gagal. Anda dapat membaca rincian baris error langsung dari menu ini tanpa perlu membuka browser web."
            local logUrl=run.optString("html_url","")
            local runId=run.optLong("id",0)
            tampilDialog("Pembangunan gagal",pesan,
                {"cek rincian error",function() PembuatAPK.bacaLogError(fullName,token,runId,logUrl) end},
                {"buka log di web",function() bukaBrowser(logUrl) end},
                {"kembali",function() PembuatAPK.menuAplikasi(fullName,token) end})
        else
            pesan=pesan.."\n\nTunggu beberapa menit, kemudian periksa lagi."
            tampilDialog("Pembangunan sedang berjalan",pesan,
                {"periksa lagi",function() PembuatAPK.cekStatus(fullName,token) end},nil,
                {"kembali",function() PembuatAPK.menuAplikasi(fullName,token) end})
        end
        if service.speak then service.speak("Status pembangunan: "..teksStatus) end
    end)
end

local function unduhLangsungKeFolderDownload(urlDownload, namaFileSimpan, tokenAuth, isZipArtifact)
    local progress = ProgressDialog(service)
    progress.setTitle("Mengunduh APK")
    progress.setMessage("Sedang mengunduh " .. namaFileSimpan .. " langsung ke folder Download...")
    progress.setCancelable(false)
    progress.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    progress.show()

    if service.speak then service.speak("Mulai mengunduh berkas APK ke folder Download.") end

    Thread(Runnable{
        run = function()
            local ok, err = pcall(function()
                local url = URL(urlDownload)
                local conn = url.openConnection()
                conn.setRequestMethod("GET")
                conn.setRequestProperty("User-Agent", "Android-Accessibility-Manager")
                if tokenAuth and tokenAuth ~= "" then
                    conn.setRequestProperty("Authorization", "Bearer " .. tokenAuth)
                end
                conn.setConnectTimeout(20000)
                conn.setReadTimeout(60000)

                local respCode = conn.getResponseCode()
                if respCode == 301 or respCode == 302 or respCode == 307 then
                    local redirectUrl = conn.getHeaderField("Location")
                    conn.disconnect()
                    url = URL(redirectUrl)
                    conn = url.openConnection()
                    conn.setRequestMethod("GET")
                    conn.setRequestProperty("User-Agent", "Android-Accessibility-Manager")
                    conn.setConnectTimeout(20000)
                    conn.setReadTimeout(60000)
                end

                local downloadDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                if not downloadDir.exists() then downloadDir.mkdirs() end

                local fileFinalPath = ""
                local isStream = conn.getInputStream()

                if isZipArtifact then
                    -- Ekstrak file .apk dari dalam zip artefak GitHub Actions
                    local zis = ZipInputStream(isStream)
                    local entry = zis.getNextEntry()
                    local apkFound = false

                    while entry ~= nil do
                        local entryName = entry.getName()
                        if entryName:lower():find("%.apk$") then
                            local cleanApkName = entryName:match("[^/]+$") or "aplikasi.apk"
                            local targetApkFile = File(downloadDir, cleanApkName)
                            local fos = FileOutputStream(targetApkFile)
                            local buf = String(string.rep(" ", 8192)).getBytes()
                            local len = zis.read(buf)
                            while len ~= -1 do
                                fos.write(buf, 0, len)
                                len = zis.read(buf)
                            end
                            fos.flush()
                            fos.close()
                            fileFinalPath = targetApkFile.getAbsolutePath()
                            apkFound = true
                            break
                        end
                        entry = zis.getNextEntry()
                    end
                    zis.close()
                    isStream.close()
                    conn.disconnect()

                    if not apkFound then
                        error("Artefak yang dipilih adalah arsip laporan pengujian, bukan berkas aplikasi. Tunggu pembangunan APK selesai atau jalankan Mulai pembangunan APK.")
                    end
                else
                    -- Unduh file .apk murni
                    local fileTarget = File(downloadDir, namaFileSimpan)
                    local fos = FileOutputStream(fileTarget)
                    local buffer = String(string.rep(" ", 8192)).getBytes()
                    local bytesRead = isStream.read(buffer)

                    while bytesRead ~= -1 do
                        fos.write(buffer, 0, bytesRead)
                        bytesRead = isStream.read(buffer)
                    end

                    fos.flush()
                    fos.close()
                    isStream.close()
                    conn.disconnect()
                    fileFinalPath = fileTarget.getAbsolutePath()
                end

                return fileFinalPath
            end)

            mainHandler.post(Runnable{
                run = function()
                    pcall(function() progress.dismiss() end)
                    if ok then
                        if service.speak then service.speak("Unduhan selesai. APK tersimpan di folder Download.") end
                        tampilDialog("APK Berhasil Disimpan",
                            "Berkas APK asli berhasil diunduh dan siap dipasang:\n\n" .. tostring(err),
                            {"pasang APK sekarang", function()
                                pcall(function()
                                    local f = File(tostring(err))
                                    local intent = Intent(Intent.ACTION_VIEW)
                                    intent.setDataAndType(Uri.fromFile(f), "application/vnd.android.package-archive")
                                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    service.startActivity(intent)
                                end)
                            end}, nil,
                            {"tutup", nil})
                    else
                        if service.speak then service.speak("Gagal mengunduh berkas.") end
                        tampilDialog("Gagal Mengunduh", "Kesalahan: " .. tostring(err),
                            {"buka di browser", function() bukaBrowser(urlDownload) end}, nil,
                            {"tutup", nil})
                    end
                end
            })
        end
    }).start()
end

function PembuatAPK.ambilAPK(fullName,token)
    local endpointRelease="https://api.github.com/repos/"..fullName.."/releases/latest"
    kirimPermintaanGitHub("GET",endpointRelease,token,nil,function(okRel,resRel)
        if okRel then
            local r=JSONObject(resRel)
            local aset=r.optJSONArray("assets")
            if aset~=nil and aset.length()>0 then
                -- Cari aset yang benar-benar berakhiran .apk
                local targetAset = nil
                for i=0, aset.length()-1 do
                    local it = aset.getJSONObject(i)
                    local nm = it.optString("name",""):lower()
                    if nm:find("%.apk$") then
                        targetAset = it
                        break
                    end
                end
                if not targetAset then targetAset = aset.getJSONObject(0) end

                local nama=targetAset.optString("name","aplikasi.apk")
                local ukuran=targetAset.optLong("size",0)
                local tautan=targetAset.optString("browser_download_url","")
                tampilDialog("APK Siap Diunduh",
                    "Nama berkas: "..nama.."\nUkuran: "..formatUkuranBerkas(ukuran).."\n\nTekan tombol unduh sekarang untuk menyimpan berkas APK langsung ke folder Download HP Anda.",
                    {"unduh sekarang",function()
                        unduhLangsungKeFolderDownload(tautan, nama, nil, false)
                    end},
                    {"salin tautan",function() salinKeClipboard("Tautan APK",tautan) end},
                    {"kembali",function() PembuatAPK.menuAplikasi(fullName,token) end})
                return
            end
        end

        -- Jika rilis belum ada, ambil dari artefak actions dan tampilkan daftarnya secara transparan
        local endpointArt="https://api.github.com/repos/"..fullName.."/actions/artifacts?per_page=20"
        kirimPermintaanGitHub("GET",endpointArt,token,nil,function(okArt,resArt)
            if okArt then
                local objArt=JSONObject(resArt)
                local arrArt=objArt.optJSONArray("artifacts")
                if arrArt~=nil and arrArt.length()>0 then
                    local daftarNama = {}
                    local daftarData = {}

                    for i=0, arrArt.length()-1 do
                        local item = arrArt.getJSONObject(i)
                        local artName = item.optString("name","")
                        local artSize = item.optLong("size_in_bytes",0)
                        table.insert(daftarNama, (i+1)..". "..artName.." ("..formatUkuranBerkas(artSize)..")")
                        table.insert(daftarData, item)
                    end

                    local bPilihArt = AlertDialog.Builder(service)
                    bPilihArt.setTitle("Pilih Berkas Artefak (" .. #daftarData .. ")")
                    bPilihArt.setItems(daftarNama, DialogInterface.OnClickListener{
                        onClick = function(dArt, whichArt)
                            local terpilih = daftarData[whichArt+1]
                            local artNama = terpilih.optString("name","aplikasi-apk")
                            local artUrl = terpilih.optString("archive_download_url","")
                            local isZip = true

                            tampilDialog("Unduh & Ekstrak APK",
                                "Berkas: "..artNama.."\n\nTekan tombol Unduh Sekarang untuk mengunduh dan otomatis mengekstrak berkas .apk ke folder Download internal HP Anda.",
                                {"unduh sekarang",function()
                                    unduhLangsungKeFolderDownload(artUrl, artNama, token, isZip)
                                end},
                                {"salin tautan",function() salinKeClipboard("Tautan Artefak",artUrl) end},
                                {"kembali",function() PembuatAPK.ambilAPK(fullName,token) end})
                        end
                    })
                    bPilihArt.setNegativeButton("kembali", DialogInterface.OnClickListener{
                        onClick = function() PembuatAPK.menuAplikasi(fullName,token) end
                    })
                    local dPArt = bPilihArt.create()
                    dPArt.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                    dPArt.show()
                    aturTombolHurufKecil(dPArt, nil, "kembali", nil)
                    if service.speak then service.speak("Ditemukan " .. #daftarData .. " berkas artefak. Silakan pilih.") end
                    return
                end
            end

            tampilDialog("APK Belum Siap",
                "Berkas pembangunan belum selesai disimpan oleh GitHub atau alur kerja masih berjalan. Silakan periksa status atau tunggu beberapa saat.",
                {"cek status",function() PembuatAPK.cekStatus(fullName,token) end},
                {"buka actions web",function() bukaBrowser("https://github.com/"..fullName.."/actions") end},
                {"kembali",function() PembuatAPK.menuAplikasi(fullName,token) end})
        end)
    end)
end

function PembuatAPK.bangunUlang(fullName,token)
    kirimPermintaanGitHub("GET","https://api.github.com/repos/"..fullName,token,nil,function(ok,res)
        if not ok then
            Toast.makeText(service,"Gagal membaca proyek: "..tostring(res),Toast.LENGTH_LONG).show()
            return
        end
        local cabang=JSONObject(res).optString("default_branch","main")
        local payload=JSONObject(); payload.put("ref",cabang)
        local endpoint="https://api.github.com/repos/"..fullName.."/actions/workflows/"..NAMA_ALUR_KERJA.."/dispatches"
        kirimPermintaanGitHub("POST",endpoint,token,payload.toString(),function(ok2,res2)
            if ok2 then
                if service.speak then service.speak("Pembangunan APK dimulai.") end
                tampilDialog("Pembangunan dimulai",
                    "GitHub mulai membangun APK. Biasanya membutuhkan beberapa menit.",
                    {"cek status",function() PembuatAPK.cekStatus(fullName,token) end},nil,
                    {"kembali",function() PembuatAPK.menuAplikasi(fullName,token) end})
            else
                Toast.makeText(service,"Gagal memulai pembangunan: "..tostring(res2),Toast.LENGTH_LONG).show()
            end
        end)
    end)
end

function PembuatAPK.kelolaBerkas(fullName,token)
    kirimPermintaanGitHub("GET","https://api.github.com/repos/"..fullName,token,nil,function(ok,res)
        if not ok then
            Toast.makeText(service,"Gagal membaca proyek: "..tostring(res),Toast.LENGTH_LONG).show()
            return
        end
        bukaDirektoriRepoDialog(fullName,"",token,JSONObject(res))
    end)
end

function PembuatAPK.bukaArtifact(fullName, token)
    local url = "https://github.com/" .. fullName .. "/actions"
    tampilDialog("Artifact dan hasil build",
        "Buka halaman Actions untuk melihat APK, AAB, mapping, laporan, dan hasil pengujian yang disimpan oleh workflow.",
        {"buka Actions", function() bukaBrowser(url) end},
        {"salin tautan", function() salinKeClipboard("Tautan Actions", url) end},
        {"kembali", function() PembuatAPK.menuAplikasi(fullName, token) end})
end

PembuatAPK.bukaPengaturanWorkflow = function(fullName, token)
    local url = "https://github.com/" .. fullName .. "/actions/workflows/" .. NAMA_ALUR_KERJA
    tampilDialog("Pengaturan workflow",
        "Di halaman ini Anda dapat melihat riwayat workflow, menjalankan workflow manual, membatalkan proses, dan membuka log setiap langkah.",
        {"buka workflow", function() bukaBrowser(url) end}, nil,
        {"kembali", function() PembuatAPK.menuAplikasi(fullName, token) end})
end

function PembuatAPK.hapusProyekGitHub(fullName,token)
    tampilDialog("Hapus proyek APK?",
        "PERINGATAN: tindakan ini menghapus repositori proyek dari GitHub secara permanen. APK dan riwayat pembangunan di repositori tersebut juga ikut hilang.",
        {"hapus permanen",function()
            kirimPermintaanGitHub("DELETE","https://api.github.com/repos/"..fullName,token,nil,function(ok,res)
                if ok then
                    local daftar=ambilDaftarAplikasi(); local baru={}
                    for _,n in ipairs(daftar) do if n~=fullName then table.insert(baru,n) end end
                    simpanDaftarAplikasi(baru)
                    Toast.makeText(service,"Proyek berhasil dihapus dari GitHub.",Toast.LENGTH_LONG).show()
                    PembuatAPK.daftar(token)
                else
                    Toast.makeText(service,"Gagal menghapus proyek: "..tostring(res),Toast.LENGTH_LONG).show()
                end
            end)
        end},nil,
        {"batalkan",function() PembuatAPK.menuAplikasi(fullName,token) end})
end

function PembuatAPK.editMainActivity(fullName, token)
    local progress = ProgressDialog(service)
    progress.setTitle("Mencari berkas utama")
    progress.setMessage("Sedang memeriksa berkas proyek...")
    progress.setCancelable(false)
    progress.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    progress.show()

    kirimPermintaanGitHub("GET", "https://api.github.com/repos/" .. fullName, token, nil, function(okRepo, resRepo)
        if not okRepo then
            pcall(function() progress.dismiss() end)
            Toast.makeText(service, "Gagal membaca repositori: " .. tostring(resRepo), Toast.LENGTH_LONG).show()
            PembuatAPK.menuAplikasi(fullName, token)
            return
        end

        local defBranch = JSONObject(resRepo).optString("default_branch", "main")
        local endpointTree = "https://api.github.com/repos/" .. fullName .. "/git/trees/" .. defBranch .. "?recursive=1"

        kirimPermintaanGitHub("GET", endpointTree, token, nil, function(okTree, resTree)
            if not okTree then
                pcall(function() progress.dismiss() end)
                Toast.makeText(service, "Gagal memeriksa daftar berkas: " .. tostring(resTree), Toast.LENGTH_LONG).show()
                PembuatAPK.menuAplikasi(fullName, token)
                return
            end

            local mainPath = nil
            pcall(function()
                local treeObj = JSONObject(resTree)
                local treeArr = treeObj.optJSONArray("tree")
                if treeArr ~= nil then
                    for i = 0, treeArr.length() - 1 do
                        local item = treeArr.getJSONObject(i)
                        local p = item.optString("path", "")
                        if p:match("MainActivity%.java$") or p:match("MainActivity%.kt$") then
                            mainPath = p
                            break
                        end
                    end
                end
            end)

            if not mainPath then
                pcall(function() progress.dismiss() end)
                if service.speak then service.speak("Berkas MainActivity tidak ditemukan.") end
                Toast.makeText(service, "Berkas MainActivity.java atau .kt tidak ditemukan di proyek ini.", Toast.LENGTH_LONG).show()
                PembuatAPK.menuAplikasi(fullName, token)
                return
            end

            pcall(function() progress.setMessage("Membuka " .. (mainPath:match("[^/]+$") or mainPath) .. "...") end)

            local endpointContent = "https://api.github.com/repos/" .. fullName .. "/contents/" .. mainPath
            kirimPermintaanGitHub("GET", endpointContent, token, nil, function(okContent, resContent)
                pcall(function() progress.dismiss() end)
                if not okContent then
                    Toast.makeText(service, "Gagal mengambil berkas: " .. tostring(resContent), Toast.LENGTH_LONG).show()
                    PembuatAPK.menuAplikasi(fullName, token)
                    return
                end

                local obj = JSONObject(resContent)
                local sha = obj.optString("sha", "")
                local base64Content = obj.optString("content", ""):gsub("%s+", "")
                local bytes = Base64.decode(base64Content, Base64.DEFAULT)
                local isiTeks = String(bytes, "UTF-8")

                if service.speak then service.speak("Membuka editor " .. (mainPath:match("[^/]+$") or "MainActivity")) end

                formEditIsiBerkas(fullName, mainPath, sha, isiTeks, token, function()
                    PembuatAPK.menuAplikasi(fullName, token)
                end, function()
                    PembuatAPK.menuAplikasi(fullName, token)
                end)
            end, true)
        end, true)
    end, true)
end

PembuatAPK.menuAplikasi = function(fullName, token)
    local item={
        "1. Periksa status pembangunan",
        "2. Unduh APK/AAB Release",
        "3. Mulai pembangunan APK",
        "4. Edit berkas MainActivity.java",
        "5. Lihat Artifact dan laporan",
        "6. Lihat workflow dan log",
        "7. Kelola berkas proyek",
        "8. Buka proyek di GitHub",
        "9. Hapus dari daftar aplikasi",
        "10. Hapus proyek dari GitHub"
    }
    local b=AlertDialog.Builder(service); b.setTitle("Kelola aplikasi\n"..fullName)
    b.setItems(item,DialogInterface.OnClickListener{onClick=function(_,which)
        if which==0 then PembuatAPK.cekStatus(fullName,token)
        elseif which==1 then PembuatAPK.ambilAPK(fullName,token)
        elseif which==2 then PembuatAPK.bangunUlang(fullName,token)
        elseif which==3 then PembuatAPK.editMainActivity(fullName,token)
        elseif which==4 then PembuatAPK.bukaArtifact(fullName,token)
        elseif which==5 then PembuatAPK.bukaPengaturanWorkflow(fullName,token)
        elseif which==6 then PembuatAPK.kelolaBerkas(fullName,token)
        elseif which==7 then bukaBrowser("https://github.com/"..fullName)
        elseif which==8 then
            local daftar=ambilDaftarAplikasi(); local baru={}
            for _,n in ipairs(daftar) do if n~=fullName then table.insert(baru,n) end end
            simpanDaftarAplikasi(baru); Toast.makeText(service,"Dihapus dari daftar aplikasi. Proyek GitHub tetap ada.",Toast.LENGTH_LONG).show(); PembuatAPK.daftar(token)
        elseif which==9 then PembuatAPK.hapusProyekGitHub(fullName,token) end
    end})
    b.setNegativeButton("kembali",DialogInterface.OnClickListener{onClick=function() PembuatAPK.daftar(token) end})
    local d=b.create(); d.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY); d.show(); aturTombolHurufKecil(d,nil,"kembali",nil)
end

function PembuatAPK.daftar(token)
    local daftar=ambilDaftarAplikasi()
    if #daftar==0 then
        tampilDialog("Aplikasi saya","Belum ada proyek aplikasi.",
            {"buat aplikasi baru",function() PembuatAPK.formAplikasiBaru(token) end},nil,
            {"kembali",function() PembuatAPK.menu(token) end})
        return
    end
    local b=AlertDialog.Builder(service); b.setTitle("Aplikasi saya")
    b.setItems(daftar,DialogInterface.OnClickListener{onClick=function(dialog,which) PembuatAPK.menuAplikasi(daftar[which+1],token) end})
    b.setNegativeButton("kembali",DialogInterface.OnClickListener{onClick=function() PembuatAPK.menu(token) end})
    local diag=b.create(); diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY); diag.show()
    aturTombolHurufKecil(diag,nil,"kembali",nil)
end

PembuatAPK.menu = function(token)
    local items={
        "1. Buat aplikasi APK Android lengkap",
        "2. Aplikasi saya",
        "3. Mulai build ulang",
        "4. Lihat status build",
        "5. Unduh APK/AAB dan artifact",
        "6. Panduan signing dan GitHub Secrets",
        "7. Panduan fitur GitHub Actions"
    }
    local b=AlertDialog.Builder(service); b.setTitle("Pusat Pembuatan APK Android")
    b.setItems(items,DialogInterface.OnClickListener{onClick=function(_,which)
        if which==0 then PembuatAPK.formAplikasiBaru(token)
        elseif which==1 then PembuatAPK.daftar(token)
        elseif which==2 then PembuatAPK.daftar(token)
        elseif which==3 then PembuatAPK.daftar(token)
        elseif which==4 then PembuatAPK.daftar(token)
        elseif which==5 then
            tampilDialog("Signing Release","Untuk signing Release yang aman, simpan keystore sebagai GitHub Secret KEYSTORE_BASE64 dan password sebagai KEYSTORE_PASSWORD, KEY_ALIAS, serta KEY_PASSWORD. Jangan memasukkan password ke source code.",
                {"buka secrets",function() bukaBrowser("https://github.com/settings/repositories") end},nil,{"kembali",function() PembuatAPK.menu(token) end})
        elseif which==6 then
            tampilDialog("Fitur GitHub Actions","Workflow dapat menjalankan beberapa job, matrix build, pemeriksaan Lint, Unit Test, instrumentation test, cache, artifact, release, dan attestation. Matrix memungkinkan satu workflow menjalankan banyak kombinasi konfigurasi. Artifact dapat menyimpan APK, AAB, laporan, dan file build setelah job selesai.",
                {"mengerti",function() PembuatAPK.menu(token) end})
        end
    end})
    b.setNegativeButton("kembali",DialogInterface.OnClickListener{onClick=function() menuUtama() end})
    local d=b.create(); d.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY); d.show(); aturTombolHurufKecil(d,nil,"kembali",nil)
end

-- ==========================================================
-- 5. MENU UTAMA & LOGIN
-- ==========================================================
menuUtama = function()
    local token = prefs.getString(KEY_TOKEN, "")
    if token == "" then
        tampilkanDialogLogin()
        return
    end

    local menuItems = {
        "1. Repositori saya",
        "2. Cari repositori",
        "3. Buat repositori baru",
        "4. Buat aplikasi (APK)",
        "5. Salin token saya",
        "6. Buat token di web",
        "7. Keluar akun",
        "8. Periksa versi baru"
    }

    local b = AlertDialog.Builder(service)
    b.setTitle("Pengelola GitHub by novan")
    b.setItems(menuItems, DialogInterface.OnClickListener{
        onClick = function(dialog, which)
            if which == 0 then
                daftarRepoSayaDialog(token)
            elseif which == 1 then
                cariRepoDialog(token)
            elseif which == 2 then
                buatRepoDialog(token)
            elseif which == 3 then
                PembuatAPK.menu(token)
            elseif which == 4 then
                salinKeClipboard("Token GitHub", token)
            elseif which == 5 then
                bukaBrowser(URL_GENERATE_TOKEN)
            elseif which == 6 then
                prefs.edit().remove(KEY_TOKEN).apply()
                if service.speak then service.speak("Token dihapus. Anda keluar.") end
                Toast.makeText(service, "Anda telah keluar.", Toast.LENGTH_SHORT).show()
            elseif which == 7 then
                cekPembaruan(true)
            end
        end
    })
    b.setNegativeButton("tutup", nil)
    local diag = b.create()
    diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    diag.show()
    aturTombolHurufKecil(diag, nil, "tutup", nil)
end

tampilkanDialogLogin = function()
    local layout = LinearLayout(service)
    layout.setOrientation(LinearLayout.VERTICAL)
    layout.setPadding(40, 20, 40, 10)

    local input = EditText(service)
    input.setHint("Tempel token di sini")
    input.setSingleLine(true)
    layout.addView(input)

    local scroll = ScrollView(service.getApplicationContext())
    scroll.setFillViewport(true)
    scroll.addView(layout)

    local b = AlertDialog.Builder(service)
    b.setTitle("Masuk akun GitHub")
    b.setMessage("Masukkan token GitHub Anda. Belum punya token atau akun? Gunakan tombol di bawah:")
    b.setView(scroll)

    b.setPositiveButton("simpan token", DialogInterface.OnClickListener{
        onClick = function()
            local t = tostring(input.getText()):match("^%s*(.-)%s*$")
            if t == "" then
                Toast.makeText(service, "Token tidak boleh kosong!", Toast.LENGTH_SHORT).show()
                return
            end
            prefs.edit().putString(KEY_TOKEN, t).apply()
            if service.speak then service.speak("Token disimpan.") end
            menuUtama()
        end
    })

    b.setNeutralButton("dapatkan token di web", DialogInterface.OnClickListener{
        onClick = function() bukaBrowser(URL_GENERATE_TOKEN) end
    })

    b.setNegativeButton("buat akun baru", DialogInterface.OnClickListener{
        onClick = function() bukaBrowser(URL_DAFTAR_AKUN) end
    })

    local diag = b.create()
    diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    diag.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
    diag.show()
    aturTombolHurufKecil(diag, "simpan token", "buat akun baru", "dapatkan token di web")
end

menuUtama()
