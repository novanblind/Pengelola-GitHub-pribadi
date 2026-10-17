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
import "java.net.URLEncoder"
import "java.lang.System"
import "java.security.KeyPairGenerator"
import "java.security.KeyStore"
import "java.security.SecureRandom"
import "java.security.Signature"
import "java.security.MessageDigest"
import "java.security.cert.CertificateFactory"
import "android.content.ContentValues"
import "android.provider.MediaStore"
import "android.media.MediaScannerConnection"
import "android.webkit.MimeTypeMap"
import "java.lang.Thread"
import "java.lang.Runnable"
import "java.util.zip.ZipInputStream"
import "java.util.zip.ZipEntry"
import "org.json.JSONObject"
import "org.json.JSONArray"

local mainHandler = Handler(Looper.getMainLooper())

local VERSI_SAAT_INI = "1.26"
local URL_RAW_SCRIPT = "https://raw.githubusercontent.com/novanblind/Pengelola-GitHub-pribadi/main/github.lua"

local infoScript = debug.getinfo(1, "S")
local JALUR_BERKAS_SCRIPT = (infoScript and infoScript.source and infoScript.source:sub(1, 1) == "@")
    and infoScript.source:sub(2) or ""

local PREF_NAME = "github_acc_manager_exclusive_unique_cfg"
local KEY_TOKEN = "key_github_user_pat_unique"
local prefs = service.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)

local menuUtama, tampilkanDialogLogin
local PembuatAPK
local buatRepoDialog, tambahFileRepoDialog, unggahDariMemoriHPDialog, konfirmUnggahBerkasDialog
local daftarRepoSayaDialog, cariRepoDialog, kelolaRepoPilihanDialog, ubahPrivasiRepoDialog
local bukaDirektoriRepoDialog, menuAksiFile, formEditIsiBerkas, gantiNamaRepoDialog, gantiNamaBerkasDialog, hapusRepoDialog
local hapusSemuaIsiFolder
local cekPembaruan, prosesDownloadPembaruan, aktifkanGitHubPagesOtomatis
local filterRepoDialog, multiSelectRepoDialog
local Pengunduh, TandaTangan
local jalankanOperasiBanyakRepo, prosesHapusBanyakRepo, prosesUbahPrivasiBanyakRepo, tampilkanHasilOperasiBanyak

local URL_GENERATE_TOKEN = "https://github.com/settings/tokens/new?description=Aksesibilitas+Android&scopes=repo,delete_repo,workflow"
local URL_DAFTAR_AKUN = "https://github.com/signup"

local function ambilWaktuTerakhirEdit(repoObj)
    local pushed = repoObj.optString("pushed_at", "")
    local updated = repoObj.optString("updated_at", "")
    return (pushed > updated) and pushed or updated
end

local function formatUkuranBerkas(bytes)
    if bytes < 1024 then
        return bytes .. " B"
    elseif bytes < 1024 * 1024 then
        return string.format("%.1f KB", bytes / 1024)
    else
        return string.format("%.1f MB", bytes / (1024 * 1024))
    end
end

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

-- Layar tetap menyala selama dialog (pemantauan build, unduh APK) tampil, agar koneksi tidak putus saat HP tidur.
local function layarTetapMenyala(diag)
    pcall(function()
        diag.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    end)
end

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

local function salinKeClipboard(label, teks)
    local clipboard = service.getSystemService(Context.CLIPBOARD_SERVICE)
    local clip = ClipData.newPlainText(label, teks)
    clipboard.setPrimaryClip(clip)
    if service.speak then service.speak(label .. " disalin.") end
    Toast.makeText(service, label .. " disalin!", Toast.LENGTH_SHORT).show()
end

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

-- Daftar repo disimpan sebentar (2 menit) agar berpindah menu terasa instan dan hemat kuota API.
local cacheRepo = {arr = nil, waktu = 0, token = nil}
local function batalkanCacheRepo() cacheRepo.arr = nil end

local BATAS_EDIT_BYTE = 1024 * 1024
local BATAS_UNGGAH_BYTE = 20 * 1024 * 1024

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
                            if metode ~= "GET" and (endpoint:find("/user/repos$")
                                or endpoint:match("^https://api%.github%.com/repos/[^/]+/[^/]+$")) then
                                batalkanCacheRepo()
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

-- muat semua repo milik sendiri (sampai 10 halaman x 100); callback(ok, JSONArray | pesanError)
local function muatSemuaRepo(token, paksa, callback)
    if not paksa and cacheRepo.arr ~= nil and cacheRepo.token == token and (os.time() - cacheRepo.waktu) < 120 then
        callback(true, cacheRepo.arr)
        return
    end

    local progress = ProgressDialog(service)
    progress.setTitle("Menghubungkan")
    progress.setMessage("Memuat daftar repositori...")
    progress.setCancelable(true)
    progress.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    progress.show()

    local semua = JSONArray()
    local function selesaiMuat(ok, hasil)
        pcall(function() progress.dismiss() end)
        callback(ok, hasil)
    end

    local function halaman(n)
        local endpoint = "https://api.github.com/user/repos?sort=updated&direction=desc&per_page=100&affiliation=owner&page=" .. n
        kirimPermintaanGitHub("GET", endpoint, token, nil, function(ok, res)
            if not ok then
                selesaiMuat(false, res)
                return
            end
            local okParse, a = pcall(function() return JSONArray(res) end)
            if not okParse then
                selesaiMuat(false, "Respons GitHub tidak valid.")
                return
            end
            for i = 0, a.length() - 1 do semua.put(a.get(i)) end
            if a.length() == 100 and n < 10 then
                pcall(function() progress.setMessage("Memuat daftar repositori (halaman " .. (n + 1) .. ")...") end)
                halaman(n + 1)
            else
                cacheRepo.arr = semua
                cacheRepo.waktu = os.time()
                cacheRepo.token = token
                selesaiMuat(true, semua)
            end
        end, true)
    end
    halaman(1)
end

daftarRepoSayaDialog = function(token, filterAktif, paksa)
    filterAktif = filterAktif or "semua"

    muatSemuaRepo(token, paksa, function(ok, res)
        if not ok then
            Toast.makeText(service, "Gagal memuat: " .. tostring(res), Toast.LENGTH_LONG).show()
            return
        end

        local okProses, hasilData = pcall(function()
            local arr = res
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
                    daftarRepoSayaDialog(token, filterAktif, true)
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

            muatSemuaRepo(token, false, function(ok, res)
                if not ok then
                    Toast.makeText(service, "Gagal mencari: " .. tostring(res), Toast.LENGTH_LONG).show()
                    return
                end

                local okFilter, hasilFilter = pcall(function()
                    local arr = res
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


-- ===== Pengunduh (v1.18): unduh berkas / ZIP repositori ke folder Download =====
Pengunduh = {}

local function bersihkanNamaBerkas(n)
    local s = tostring(n):gsub('[\\/:*?"<>|]', "_")
    s = s:match("^%s*(.-)%s*$")
    if s == "" then s = "berkas" end
    return s
end

local function tebakMime(nama)
    local ext = nama:match("%.([^.]+)$")
    if ext then
        local okM, m = pcall(function()
            return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext:lower())
        end)
        if okM and m then return tostring(m) end
    end
    return "application/octet-stream"
end

local function enkodeJalur(jalur)
    local bagian = {}
    for seg in tostring(jalur):gmatch("[^/]+") do
        local e = tostring(URLEncoder.encode(seg, "UTF-8")):gsub("%+", "%%20")
        table.insert(bagian, e)
    end
    return table.concat(bagian, "/")
end

-- buat berkas tujuan di folder Download (MediaStore di Android 10+, berkas biasa di bawahnya)
local function buatTargetDownload(nama, mime)
    local t = {nama = nama}
    if Build.VERSION.SDK_INT >= 29 then
        local v = ContentValues()
        v.put(MediaStore.MediaColumns.DISPLAY_NAME, nama)
        v.put(MediaStore.MediaColumns.MIME_TYPE, mime)
        v.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
        local cr = service.getContentResolver()
        local u = cr.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v)
        if u == nil then error("Tidak bisa membuat berkas di folder Download") end
        t.uri = u
        t.os = cr.openOutputStream(u)
        if t.os == nil then error("Tidak bisa menulis berkas") end
    else
        local dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if not dir.exists() then dir.mkdirs() end
        local dasar, ekst = nama, ""
        local titik = nama:match("^.*()%.")
        if titik and titik > 1 then
            dasar = nama:sub(1, titik - 1)
            ekst = nama:sub(titik)
        end
        local f = File(dir, nama)
        local n = 1
        while f.exists() do
            f = File(dir, dasar .. " (" .. n .. ")" .. ekst)
            n = n + 1
        end
        t.file = f
        t.nama = tostring(f.getName())
        t.os = FileOutputStream(f)
    end
    return t
end

local function batalkanTarget(t)
    if not t then return end
    pcall(function() if t.os then t.os.close() end end)
    pcall(function()
        if t.uri then service.getContentResolver().delete(t.uri, nil, nil) end
        if t.file then t.file.delete() end
    end)
end

-- buka koneksi; pengalihan diikuti manual agar token tidak terkirim ke host lain
local function bukaKoneksiAman(urlAwal, token, accept)
    local cur = urlAwal
    local kirimAuth = true
    for _ = 1, 5 do
        local c = URL(cur).openConnection()
        c.setInstanceFollowRedirects(false)
        c.setConnectTimeout(15000)
        c.setReadTimeout(60000)
        c.setRequestProperty("User-Agent", "Android-Accessibility-Manager")
        c.setRequestProperty("Accept", accept)
        if kirimAuth and token then
            c.setRequestProperty("Authorization", "Bearer " .. token)
        end
        local code = c.getResponseCode()
        if code >= 300 and code < 400 then
            local loc = c.getHeaderField("Location")
            c.disconnect()
            if loc == nil then error("Pengalihan tidak valid") end
            local basis = URL(cur)
            local berikut = URL(basis, loc)
            if tostring(berikut.getHost()) ~= tostring(basis.getHost()) then
                kirimAuth = false
            end
            cur = tostring(berikut.toString())
        else
            return c, code
        end
    end
    error("Terlalu banyak pengalihan")
end

-- unduh satu alamat ke folder Download. kembali: fungsi tanpa argumen untuk tombol "oke"
function Pengunduh.unduh(url, token, namaBerkas, accept, kembali)
    local nama = bersihkanNamaBerkas(namaBerkas)
    local batal = false

    local progress = ProgressDialog(service)
    progress.setTitle("Mengunduh")
    progress.setMessage("Mulai mengunduh " .. nama .. "...")
    progress.setCancelable(true)
    progress.setOnCancelListener(DialogInterface.OnCancelListener{
        onCancel = function() batal = true end
    })
    progress.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    progress.show()
    if service.speak then service.speak("Mulai mengunduh " .. nama) end

    Thread(Runnable{
        run = function()
            local hasilNama = nil
            local pesanGalat = nil

            for percobaan = 1, MAX_PERCOBAAN_JARINGAN do
                local target = nil
                local ok, err = pcall(function()
                    local c, code = bukaKoneksiAman(url, token, accept)
                    if code >= 400 then
                        local rincian = "Kode " .. code
                        if code == 404 then rincian = "Berkas tidak ditemukan (kode 404)"
                        elseif code == 403 then rincian = "Akses ditolak atau batas API tercapai (kode 403)" end
                        error("Gagal. Kode: " .. code .. " - " .. rincian)
                    end
                    target = buatTargetDownload(nama, tebakMime(nama))
                    local masuk = c.getInputStream()
                    local buf = String(string.rep(" ", 16384)).getBytes()
                    local total, terakhir = 0, 0
                    local n = masuk.read(buf)
                    while n ~= -1 do
                        if batal then error("Gagal. Kode: 0 - Unduhan dibatalkan") end
                        target.os.write(buf, 0, n)
                        total = total + n
                        local sekarang = System.currentTimeMillis()
                        if sekarang - terakhir > 500 then
                            terakhir = sekarang
                            local tt = total
                            mainHandler.post(Runnable{
                                run = function()
                                    pcall(function()
                                        progress.setMessage("Mengunduh " .. nama .. ": " .. formatUkuranBerkas(tt))
                                    end)
                                end
                            })
                        end
                        n = masuk.read(buf)
                    end
                    masuk.close()
                    target.os.flush()
                    target.os.close()
                    c.disconnect()
                    if target.file and Build.VERSION.SDK_INT < 29 then
                        pcall(function()
                            MediaScannerConnection.scanFile(service,
                                String{tostring(target.file.getAbsolutePath())}, nil, nil)
                        end)
                    end
                    hasilNama = target.nama
                end)

                if ok then
                    pesanGalat = nil
                    break
                end
                batalkanTarget(target)
                pesanGalat = tostring(err)
                if batal or not apakahErrorJaringan(pesanGalat) or percobaan >= MAX_PERCOBAAN_JARINGAN then
                    break
                end
                mainHandler.post(Runnable{
                    run = function()
                        pcall(function()
                            progress.setMessage("Koneksi gagal, mencoba lagi (" .. (percobaan + 1) .. "/" .. MAX_PERCOBAAN_JARINGAN .. ")...")
                        end)
                    end
                })
                Thread.sleep(JEDA_DASAR_RETRY_MS * percobaan)
            end

            mainHandler.post(Runnable{
                run = function()
                    pcall(function() progress.dismiss() end)
                    local sukses = (pesanGalat == nil and hasilNama ~= nil)
                    local judul, pesan
                    if sukses then
                        judul = "Unduhan selesai"
                        pesan = "Berhasil. Berkas " .. hasilNama .. " tersimpan di folder Download."
                    else
                        judul = "Unduhan gagal"
                        pesan = "Gagal mengunduh: " .. tostring(pesanGalat)
                    end
                    if service.speak then service.speak(pesan) end
                    local d = AlertDialog.Builder(service)
                    d.setTitle(judul)
                    d.setMessage(pesan)
                    d.setPositiveButton("oke", DialogInterface.OnClickListener{
                        onClick = function() if kembali then kembali() end end
                    })
                    local diag = d.create()
                    diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                    diag.show()
                    aturTombolHurufKecil(diag, "oke", nil, nil)
                end
            })
        end
    }).start()
end

-- simpan data kecil (misalnya keystore) langsung ke folder Download; mengembalikan lokasi tampilannya
function Pengunduh.simpanBytes(nama, mime, data)
    local t = buatTargetDownload(bersihkanNamaBerkas(nama), mime)
    local ok, err = pcall(function()
        t.os.write(data)
        t.os.flush()
        t.os.close()
    end)
    if not ok then
        batalkanTarget(t)
        error(tostring(err))
    end
    if t.file and Build.VERSION.SDK_INT < 29 then
        pcall(function()
            MediaScannerConnection.scanFile(service, String{tostring(t.file.getAbsolutePath())}, nil, nil)
        end)
    end
    if t.file then return tostring(t.file.getAbsolutePath()) end
    return "Download/" .. t.nama
end

function Pengunduh.unduhBerkasRepo(fullName, jalur, token, namaBerkas, kembali)
    local url = "https://api.github.com/repos/" .. fullName .. "/contents/" .. enkodeJalur(jalur)
    Pengunduh.unduh(url, token, namaBerkas, "application/vnd.github.raw+json", kembali)
end

function Pengunduh.unduhZipRepo(fullName, namaRepo, token, kembali)
    local url = "https://api.github.com/repos/" .. fullName .. "/zipball"
    Pengunduh.unduh(url, token, namaRepo .. ".zip", "application/vnd.github+json", kembali)
end

kelolaRepoPilihanDialog = function(repoObj, token)
    local namaRepo = repoObj.optString("name", "")
    local fullName = repoObj.optString("full_name", "")
    local htmlUrl = repoObj.optString("html_url", "")
    local isPrivate = repoObj.optBoolean("private", false)

    local kembaliKeRepo = function() kelolaRepoPilihanDialog(repoObj, token) end
    local subMenus = {
        "1. Buka berkas",
        "2. Tambah berkas (ketik teks)",
        "3. Unggah berkas dari HP",
        "4. Bangun APK dari repo ini",
        "5. Cek status pembangunan APK",
        "6. Unduh APK terbaru",
        "7. Unduh repositori sebagai ZIP",
        "8. Ubah status privasi (" .. (isPrivate and "saat ini privat" or "saat ini publik") .. ")",
        "9. Ganti nama repo",
        "10. Salin tautan repo",
        "11. Bagikan tautan repo",
        "12. Buka di browser",
        "13. Hapus repositori"
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
                TandaTangan.mulai(fullName, token, kembaliKeRepo)
            elseif which == 4 then
                PembuatAPK.cekStatus(fullName, token, kembaliKeRepo)
            elseif which == 5 then
                PembuatAPK.ambilAPK(fullName, token, kembaliKeRepo)
            elseif which == 6 then
                Pengunduh.unduhZipRepo(fullName, namaRepo, token, kembaliKeRepo)
            elseif which == 7 then
                ubahPrivasiRepoDialog(repoObj, token)
            elseif which == 8 then
                gantiNamaRepoDialog(repoObj, token)
            elseif which == 9 then
                salinKeClipboard("Tautan repo", htmlUrl)
            elseif which == 10 then
                bagikanTautan("Repo: " .. namaRepo, htmlUrl)
            elseif which == 11 then
                bukaBrowser(htmlUrl)
            elseif which == 12 then
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

konfirmUnggahBerkasDialog = function(fullName, token, repoObj, pathSekarang, terpilih, folderRepo)
    local layoutKonfirm = LinearLayout(service)
    layoutKonfirm.setOrientation(LinearLayout.VERTICAL)
    layoutKonfirm.setPadding(40, 20, 40, 10)

    local lblTarget = TextView(service)
    lblTarget.setText("Nama berkas di GitHub (boleh pakai folder, contoh: app/src/main/AndroidManifest.xml):")
    layoutKonfirm.addView(lblTarget)

    local inputNamaRepo = EditText(service)
    local namaAwal = tostring(terpilih.getName())
    if folderRepo and folderRepo ~= "" then namaAwal = folderRepo .. "/" .. namaAwal end
    inputNamaRepo.setText(namaAwal)
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
            if namaDiRepo == "" then namaDiRepo = namaAwal end

            if terpilih.length() > BATAS_UNGGAH_BYTE then
                local pesanUnggah = "Berkas lebih dari 20 MB, terlalu besar untuk diunggah."
                if service.speak then service.speak(pesanUnggah) end
                Toast.makeText(service, pesanUnggah, Toast.LENGTH_LONG).show()
                unggahDariMemoriHPDialog(fullName, token, repoObj, pathSekarang, folderRepo)
                return
            end

            local okB64, b64Data = pcall(function() return bacaBerkasKeBase64(terpilih) end)
            if not okB64 then
                Toast.makeText(service, "Gagal membaca berkas: " .. tostring(b64Data), Toast.LENGTH_SHORT).show()
                return
            end

            local namaAman = (namaDiRepo:gsub("^/+", "")):gsub(" ", "%%20")
            local endpoint = "https://api.github.com/repos/" .. fullName .. "/contents/" .. namaAman
            local kembaliRepo = function()
                if folderRepo then
                    bukaDirektoriRepoDialog(fullName, folderRepo, token, repoObj)
                else
                    kelolaRepoPilihanDialog(repoObj, token)
                end
            end

            local function kirimUnggah(shaLama)
                local payload = JSONObject()
                payload.put("message", (shaLama and "Perbarui " or "Unggah ") .. namaDiRepo .. " dari HP")
                payload.put("content", b64Data)
                if shaLama then payload.put("sha", shaLama) end

                kirimPermintaanGitHub("PUT", endpoint, token, payload.toString(), function(sukses, resPut)
                    if sukses then
                        local rawUrl, htmlUrl = "", ""
                        pcall(function()
                            local contentObj = JSONObject(resPut).optJSONObject("content")
                            if contentObj then
                                rawUrl = contentObj.optString("download_url", "")
                                htmlUrl = contentObj.optString("html_url", "")
                            end
                        end)
                        PembuatAPK.setelahUnggah(fullName, token, repoObj, pathSekarang, namaDiRepo, rawUrl, htmlUrl, shaLama ~= nil, folderRepo)
                    else
                        PembuatAPK.tampilError("Gagal mengunggah berkas",
                            "Berkas: " .. namaDiRepo .. "\nRepo: " .. fullName .. "\n\n" .. tostring(resPut),
                            kembaliRepo)
                    end
                end)
            end

            -- catat nomor pembangunan terakhir (untuk pemantauan), lalu cek apakah berkas sudah ada
            PembuatAPK.ambilIdRunTerakhir(fullName, token, function(idAwal)
                PembuatAPK.baselineRun[fullName] = idAwal
                kirimPermintaanGitHub("GET", endpoint, token, nil, function(adaBerkas, resBerkas)
                    local shaLama = nil
                    if adaBerkas then
                        pcall(function() shaLama = JSONObject(resBerkas).optString("sha", "") end)
                        if shaLama == "" then shaLama = nil end
                    end
                    kirimUnggah(shaLama)
                end, true)
            end)
        end
    })
    dKonfirm.setNegativeButton("kembali", DialogInterface.OnClickListener{
        onClick = function()
            unggahDariMemoriHPDialog(fullName, token, repoObj, pathSekarang, folderRepo)
        end
    })
    local dK = dKonfirm.create()
    dK.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    dK.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
    dK.show()
    aturTombolHurufKecil(dK, "unggah berkas", "kembali", nil)
end

unggahDariMemoriHPDialog = function(fullName, token, repoObj, pathSekarang, folderRepo)
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
                    unggahDariMemoriHPDialog(fullName, token, repoObj, item.path or rootPath, folderRepo)
                elseif item.tipe == "dir" then
                    unggahDariMemoriHPDialog(fullName, token, repoObj, item.file.getAbsolutePath(), folderRepo)
                elseif item.tipe == "file" then
                    konfirmUnggahBerkasDialog(fullName, token, repoObj, pathSekarang, item.file, folderRepo)
                end
            end
        })
    end

    b.setNegativeButton("kembali", DialogInterface.OnClickListener{
        onClick = function()
            if folderRepo then
                bukaDirektoriRepoDialog(fullName, folderRepo, token, repoObj)
            else
                kelolaRepoPilihanDialog(repoObj, token)
            end
        end
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
            if namaBaru:find("/", 1, true) then
                local pesanMiring = "Nama berkas tidak boleh mengandung garis miring."
                if service.speak then service.speak(pesanMiring) end
                Toast.makeText(service, pesanMiring, Toast.LENGTH_LONG).show()
                gantiNamaBerkasDialog(fullName, fileData, token, currentPath, repoObj)
                return
            end

            local jalurBaru = (currentPath == "") and namaBaru or (currentPath .. "/" .. namaBaru)
            local endpointAmbil = "https://api.github.com/repos/" .. fullName .. "/git/blobs/" .. fileData.sha

            kirimPermintaanGitHub("GET", endpointAmbil, token, nil, function(okGet, resGet)
                if not okGet then
                    Toast.makeText(service, "Gagal mengambil berkas: " .. tostring(resGet), Toast.LENGTH_LONG).show()
                    menuAksiFile(fullName, fileData, token, currentPath, repoObj)
                    return
                end

                local objGet = JSONObject(resGet)
                local shaLama = fileData.sha
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
                    payloadHapus.put("message", "Hapus " .. namaLama .. " (diganti nama)")
                    payloadHapus.put("sha", shaLama)

                    kirimPermintaanGitHub("DELETE", endpointHapus, token, payloadHapus.toString(), function(okDel, resDel)
                        if okDel then
                            if service.speak then service.speak("Nama berkas berhasil diubah menjadi " .. namaBaru) end
                            Toast.makeText(service, "Nama berkas diperbarui!", Toast.LENGTH_SHORT).show()
                            bukaDirektoriRepoDialog(fullName, currentPath, token, repoObj)
                        else
                            Toast.makeText(service, "Berkas baru dibuat, tetapi gagal menghapus yang lama: " .. tostring(resDel), Toast.LENGTH_LONG).show()
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

            local ukuranBerkas = item.optLong("size", 0)
            local labelItem = awalan .. name
            if tipe ~= "dir" then labelItem = labelItem .. ", " .. formatUkuranBerkas(ukuranBerkas) end
            table.insert(menuItems, labelItem)
            table.insert(dataItems, {
                tipe = tipe,
                name = name,
                size = ukuranBerkas,
                path = item.optString("path", ""),
                sha = item.optString("sha", ""),
                html_url = item.optString("html_url", ""),
                download_url = item.optString("download_url", "")
            })
        end

        local adaIsi = (total > 0)
        table.insert(menuItems, "Unggah berkas dari HP ke folder ini")
        table.insert(dataItems, {tipe = "unggah_di_sini"})
        table.insert(menuItems, "Tambah berkas teks baru di folder ini")
        table.insert(dataItems, {tipe = "tambah_di_sini"})
        if adaIsi then
            table.insert(menuItems, "Hapus semua berkas di folder ini")
            table.insert(dataItems, {tipe = "hapus_semua"})
        end

        local judul = (currentPath == "") and ("Berkas: " .. repoObj.optString("name", "")) or ("Folder: " .. currentPath)
        if not adaIsi then judul = judul .. " (folder ini kosong)" end
        local b = AlertDialog.Builder(service)
        b.setTitle(judul)

        do
            b.setItems(menuItems, DialogInterface.OnClickListener{
                onClick = function(dialog, which)
                    local data = dataItems[which + 1]
                    if data.tipe == "kembali_folder" then
                        local parentPath = currentPath:match("^(.*)/[^/]+$") or ""
                        bukaDirektoriRepoDialog(fullName, parentPath, token, repoObj)
                    elseif data.tipe == "dir" then
                        bukaDirektoriRepoDialog(fullName, data.path, token, repoObj)
                    elseif data.tipe == "unggah_di_sini" then
                        unggahDariMemoriHPDialog(fullName, token, repoObj,
                            tostring(Environment.getExternalStorageDirectory().getAbsolutePath()), currentPath)
                    elseif data.tipe == "tambah_di_sini" then
                        tambahFileRepoDialog(token, fullName, repoObj, currentPath)
                    elseif data.tipe == "hapus_semua" then
                        local lokasi = (currentPath == "") and ("seluruh repositori " .. repoObj.optString("name", "")) or ("folder " .. currentPath)
                        local kembaliKeFolder = DialogInterface.OnClickListener{
                            onClick = function() bukaDirektoriRepoDialog(fullName, currentPath, token, repoObj) end
                        }
                        local k1 = AlertDialog.Builder(service)
                        k1.setTitle("Hapus semua berkas?")
                        k1.setMessage("Semua berkas dan folder di dalam " .. lokasi .. " akan dihapus, termasuk isi semua subfolder. Lanjutkan?")
                        k1.setPositiveButton("lanjut", DialogInterface.OnClickListener{
                            onClick = function()
                                local k2 = AlertDialog.Builder(service)
                                k2.setTitle("Yakin hapus semua?")
                                k2.setMessage("Ini penghapusan terakhir untuk " .. lokasi .. ". Setiap berkas dihapus lewat satu komit di GitHub dan tidak bisa dibatalkan dari skrip ini.")
                                k2.setPositiveButton("hapus semua", DialogInterface.OnClickListener{
                                    onClick = function() hapusSemuaIsiFolder(fullName, currentPath, token, repoObj) end
                                })
                                k2.setNegativeButton("batal", kembaliKeFolder)
                                local dK2 = k2.create()
                                dK2.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                                dK2.show()
                                aturTombolHurufKecil(dK2, "hapus semua", "batal", nil)
                            end
                        })
                        k1.setNegativeButton("batal", kembaliKeFolder)
                        local dK1 = k1.create()
                        dK1.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                        dK1.show()
                        aturTombolHurufKecil(dK1, "lanjut", "batal", nil)
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

hapusSemuaIsiFolder = function(fullName, currentPath, token, repoObj)
    local progress = ProgressDialog(service)
    progress.setTitle("Hapus semua berkas")
    progress.setMessage("Menghitung berkas yang akan dihapus...")
    progress.setCancelable(false)
    progress.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    progress.show()

    local function tutup()
        pcall(function() progress.dismiss() end)
    end

    local function kembaliKeFolder()
        bukaDirektoriRepoDialog(fullName, currentPath, token, repoObj)
    end

    local daftar = {}
    local antrean = {currentPath}

    local function mulaiHapus()
        local total = #daftar
        if total == 0 then
            tutup()
            Toast.makeText(service, "Tidak ada berkas untuk dihapus.", Toast.LENGTH_SHORT).show()
            kembaliKeFolder()
            return
        end
        if service.speak then service.speak("Menghapus " .. total .. " berkas. Mohon tunggu.") end

        local berhasil, gagal, galatTerakhir = 0, 0, ""

        local function hapusKe(i, percobaan)
            if i > total then
                tutup()
                local pesan = "Selesai. " .. berhasil .. " berkas dihapus."
                if gagal > 0 then
                    pesan = pesan .. " " .. gagal .. " berkas gagal dihapus. Galat terakhir: " .. galatTerakhir
                end
                pesan = pesan .. " Bila masih ada sisa, pilih hapus semua sekali lagi."
                if service.speak then service.speak(pesan) end
                local d = AlertDialog.Builder(service)
                d.setTitle("Hapus semua selesai")
                d.setMessage(pesan)
                d.setPositiveButton("oke", DialogInterface.OnClickListener{
                    onClick = function() kembaliKeFolder() end
                })
                d.setCancelable(false)
                local diag = d.create()
                diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                diag.show()
                aturTombolHurufKecil(diag, "oke", nil, nil)
                return
            end

            local f = daftar[i]
            pcall(function()
                progress.setMessage("Menghapus " .. i .. " dari " .. total .. ": " .. f.nama)
            end)

            local payload = JSONObject()
            payload.put("message", "Hapus " .. f.path .. " [skip ci]")
            payload.put("sha", f.sha)
            local endpoint = "https://api.github.com/repos/" .. fullName .. "/contents/" .. enkodeJalur(f.path)
            kirimPermintaanGitHub("DELETE", endpoint, token, payload.toString(), function(ok, res)
                if ok then
                    berhasil = berhasil + 1
                    hapusKe(i + 1, 1)
                elseif tostring(res):find("Kode: 409", 1, true) and percobaan < 3 then
                    -- 409 = komit lain sedang berjalan di GitHub; coba lagi sebentar kemudian.
                    mainHandler.postDelayed(Runnable{
                        run = function() hapusKe(i, percobaan + 1) end
                    }, 1500 * percobaan)
                else
                    gagal = gagal + 1
                    galatTerakhir = tostring(res)
                    hapusKe(i + 1, 1)
                end
            end, true)
        end

        hapusKe(1, 1)
    end

    local function kumpul()
        if #antrean == 0 then
            mulaiHapus()
            return
        end
        local p = table.remove(antrean, 1)
        local endpoint = "https://api.github.com/repos/" .. fullName .. "/contents"
        if p ~= "" then endpoint = endpoint .. "/" .. enkodeJalur(p) end
        kirimPermintaanGitHub("GET", endpoint, token, nil, function(ok, res)
            if not ok then
                tutup()
                Toast.makeText(service, "Gagal membaca " .. ((p == "") and "folder utama" or p) .. ": " .. tostring(res), Toast.LENGTH_LONG).show()
                kembaliKeFolder()
                return
            end
            local okParse, arr = pcall(function() return JSONArray(res) end)
            if okParse and arr then
                for i = 0, arr.length() - 1 do
                    local it = arr.getJSONObject(i)
                    local tipe = it.optString("type", "")
                    local jalur = it.optString("path", "")
                    if tipe == "dir" then
                        table.insert(antrean, jalur)
                    elseif tipe ~= "submodule" then
                        table.insert(daftar, {path = jalur, sha = it.optString("sha", ""), nama = it.optString("name", "")})
                    end
                end
            end
            kumpul()
        end, true)
    end

    kumpul()
end

menuAksiFile = function(fullName, fileData, token, currentPath, repoObj)
    local opsiFile = {
        "1. Unduh berkas",
        "2. Salin tautan raw (updater)",
        "3. Edit isi berkas",
        "4. Ganti nama berkas",
        "5. Salin tautan web",
        "6. Bagikan tautan raw",
        "7. Hapus berkas"
    }

    local b = AlertDialog.Builder(service)
    b.setTitle("Berkas: " .. fileData.name)
    b.setItems(opsiFile, DialogInterface.OnClickListener{
        onClick = function(dialog, which)
            if which == 0 then
                Pengunduh.unduhBerkasRepo(fullName, fileData.path, token, fileData.name, function()
                    menuAksiFile(fullName, fileData, token, currentPath, repoObj)
                end)
            elseif which == 1 then
                salinKeClipboard("Tautan raw", fileData.download_url)
            elseif which == 2 then
                if (fileData.size or 0) > BATAS_EDIT_BYTE then
                    local pesanBesar = "Berkas lebih dari 1 MB, terlalu besar untuk diedit di sini. Gunakan menu unduh berkas."
                    if service.speak then service.speak(pesanBesar) end
                    Toast.makeText(service, pesanBesar, Toast.LENGTH_LONG).show()
                    menuAksiFile(fullName, fileData, token, currentPath, repoObj)
                    return
                end
                local endpoint = "https://api.github.com/repos/" .. fullName .. "/contents/" .. fileData.path
                kirimPermintaanGitHub("GET", endpoint, token, nil, function(ok, res)
                    if ok then
                        local obj = JSONObject(res)
                        local sha = obj.optString("sha", "")
                        local base64Content = obj.optString("content", ""):gsub("%s+", "")
                        local bytes = Base64.decode(base64Content, Base64.DEFAULT)
                        local isiTeks = String(bytes, "UTF-8")
                        if tostring(isiTeks):find("\0", 1, true) then
                            local pesanBukanTeks = "Berkas ini bukan teks sehingga tidak bisa diedit. Gunakan menu unduh berkas."
                            if service.speak then service.speak(pesanBukanTeks) end
                            Toast.makeText(service, pesanBukanTeks, Toast.LENGTH_LONG).show()
                            menuAksiFile(fullName, fileData, token, currentPath, repoObj)
                            return
                        end

                        formEditIsiBerkas(fullName, fileData.path, sha, isiTeks, token, function()
                            bukaDirektoriRepoDialog(fullName, currentPath, token, repoObj)
                        end, function()
                            menuAksiFile(fullName, fileData, token, currentPath, repoObj)
                        end)
                    else
                        Toast.makeText(service, "Gagal membaca: " .. tostring(res), Toast.LENGTH_LONG).show()
                    end
                end)
            elseif which == 3 then
                gantiNamaBerkasDialog(fullName, fileData, token, currentPath, repoObj)
            elseif which == 4 then
                salinKeClipboard("Tautan web", fileData.html_url)
            elseif which == 5 then
                bagikanTautan("Berkas raw: " .. fileData.name, fileData.download_url)
            elseif which == 6 then
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

buatRepoDialog = function(token, awal)
    awal = awal or {}
    local layout = LinearLayout(service)
    layout.setOrientation(LinearLayout.VERTICAL)
    layout.setPadding(40, 20, 40, 10)

    local lblNama = TextView(service)
    lblNama.setText("Nama repo:")
    layout.addView(lblNama)

    local inputNama = EditText(service)
    inputNama.setHint("contoh: skrip-baru")
    inputNama.setSingleLine(true)
    if awal.nama and awal.nama ~= "" then inputNama.setText(awal.nama) end
    layout.addView(inputNama)

    local lblDesc = TextView(service)
    lblDesc.setText("Deskripsi:")
    lblDesc.setPadding(0, 15, 0, 0)
    layout.addView(lblDesc)

    local inputDesc = EditText(service)
    inputDesc.setHint("Keterangan singkat")
    inputDesc.setSingleLine(true)
    if awal.desc and awal.desc ~= "" then inputDesc.setText(awal.desc) end
    layout.addView(inputDesc)

    local chkPrivate = CheckBox(service)
    chkPrivate.setText("Jadikan privat")
    chkPrivate.setChecked(awal.privat and true or false)
    layout.addView(chkPrivate)

    local chkReadme = CheckBox(service)
    chkReadme.setText("Tambahkan README (GitHub Pages ikut diaktifkan)")
    chkReadme.setChecked(awal.readme and true or false)
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
            local isiForm = {nama = nama, desc = desc, privat = chkPrivate.isChecked(), readme = chkReadme.isChecked()}
            if nama == "" then
                if service.speak then service.speak("Nama repo wajib diisi.") end
                Toast.makeText(service, "Nama repo wajib diisi.", Toast.LENGTH_SHORT).show()
                buatRepoDialog(token, isiForm)
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

                                PembuatAPK.dialogTombol("Repositori dibuat", pesanDialog, {
                                    {"salin tautan", function() salinKeClipboard("Tautan repo", htmlUrl) end, tetap = true},
                                    {"bagikan", function() bagikanTautan("Repo: " .. nama, htmlUrl) end, tetap = true},
                                    {"buka repositori", function() kelolaRepoPilihanDialog(obj, token) end},
                                }, {"kembali", function() menuUtama() end})
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
                    Toast.makeText(service, "Gagal membuat repo. " .. tostring(res), Toast.LENGTH_LONG).show()
                    buatRepoDialog(token, isiForm)
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

tambahFileRepoDialog = function(token, repoOtomatis, repoObj, folderRepo)
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
    if folderRepo and folderRepo ~= "" then
        inputPath.setText(folderRepo .. "/")
        inputPath.setSelection(inputPath.getText().length())
    end
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

                    local kembaliKeRepo = function()
                        if repoObj and folderRepo then
                            bukaDirektoriRepoDialog(repo, folderRepo, token, repoObj)
                        elseif repoObj then
                            kelolaRepoPilihanDialog(repoObj, token)
                        else
                            menuUtama()
                        end
                    end
                    local tampilkanMenuSesudahSimpan
                    tampilkanMenuSesudahSimpan = function()
                        local pilihan = {
                            "1. Bangun APK dari repo ini",
                            "2. Cek status pembangunan APK",
                            "3. Salin tautan raw",
                            "4. Bagikan",
                            "5. Tambah berkas lain"
                        }
                        local d = AlertDialog.Builder(service)
                        d.setTitle("Berkas ditambahkan\n" .. path .. "\nRepositori: " .. repo)
                        d.setItems(pilihan, DialogInterface.OnClickListener{
                            onClick = function(_, which)
                                if which == 0 then
                                    TandaTangan.mulai(repo, token, tampilkanMenuSesudahSimpan)
                                elseif which == 1 then
                                    PembuatAPK.cekStatus(repo, token, tampilkanMenuSesudahSimpan)
                                elseif which == 2 then
                                    salinKeClipboard("Tautan raw", rawUrl)
                                    tampilkanMenuSesudahSimpan()
                                elseif which == 3 then
                                    bagikanTautan("Berkas: " .. path, rawUrl ~= "" and rawUrl or fileUrl)
                                elseif which == 4 then
                                    tambahFileRepoDialog(token, repo, repoObj, folderRepo)
                                end
                            end
                        })
                        d.setNegativeButton("kembali", DialogInterface.OnClickListener{
                            onClick = function() kembaliKeRepo() end
                        })
                        local diag = d.create()
                        diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                        diag.show()
                        aturTombolHurufKecil(diag, nil, "kembali", nil)
                    end
                    if service.speak then service.speak("Berkas ditambahkan.") end
                    tampilkanMenuSesudahSimpan()
                else
                    Toast.makeText(service, "Gagal: " .. tostring(res), Toast.LENGTH_LONG).show()
                end
            end)
        end
    })
    b.setNegativeButton("kembali", DialogInterface.OnClickListener{
        onClick = function()
            if repoObj and folderRepo then
                bukaDirektoriRepoDialog(tostring(inputRepo.getText()):match("^%s*(.-)%s*$"), folderRepo, token, repoObj)
            elseif repoObj then
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

PembuatAPK = {}
PembuatAPK.baselineRun = {}
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
    id 'com.android.application' version '8.7.0' apply false
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

Aplikasi Android yang dibuat melalui **GitHub By Novan**.

* **Paket**: `@@PAKET@@`
* **Versi**: `@@VERSI@@` (Kode versi: `@@VERSION_CODE@@`)
* **Target SDK**: Android @@TARGET_SDK@@ (Minimal Android @@MIN_SDK@@)

---

## Pembangunan APK Otomatis

Proyek ini dibangun secara otomatis menggunakan alur kerja GitHub Actions (`.github/workflows/bangun-apk.yml`).

Setiap kali alur kerja dijalankan (melalui tombol **Mulai pembangunan APK** di aplikasi atau lewat pemicu commit/manual di GitHub), APK akan langsung dikompilasi.

---

## Metode Penandatanganan APK (Signing)

Alur kerja build mendukung dua opsi penandatanganan:

* **Tanda Tangan Pribadi (Release)**:
  * Aktif otomatis jika berkas `.tanda-tangan/kunci.p12` dan `.tanda-tangan/sandi.properties` tersedia di repositori.
  * APK dikompilasi dalam varian Release dan ditandatangani menggunakan sertifikat PKCS12 pribadi.
  * Aplikasi yang sudah dipasang di perangkat Android dapat selalu diperbarui (*update*) tanpa perlu mencopot versi lama.
  * **Keamanan**: Pastikan repositori ini selalu bersifat **privat** agar sertifikat dan kata sandi Anda tetap terlindungi.

* **Tanda Tangan Bawaan GitHub (Debug)**:
  * Digunakan jika folder `.tanda-tangan` tidak ada di repositori.
  * APK dikompilasi dalam varian Debug menggunakan kunci sementara bawaan runner GitHub Actions.
  * Cocok untuk pengujian cepat. Karena kunci runner berganti di setiap pembangunan baru, pembaruan aplikasi mengharuskan pencopotan (*uninstall*) versi lama terlebih dahulu.

---

## Unduh Berkas APK

Setelah proses pembangunan selesai, berkas APK dapat diunduh melalui:
* **GitHub Releases**: Berkas APK siap pasang otomatis terbit di tab **Releases** dengan tag `v<nomor_build>`.
* **GitHub Actions (Artifacts)**: Berkas APK juga tersimpan sebagai artefak pada riwayat alur kerja build terkait.
]==]

TEMPLAT.workflowLengkap = [==[
# tanda-tangan-pribadi: v2
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

      - name: Periksa tanda tangan pribadi
        id: tt
        run: |
          if [ -f .tanda-tangan/kunci.p12 ] && [ -f .tanda-tangan/sandi.properties ]; then
            echo "pribadi=true" >> "$GITHUB_OUTPUT"
            echo "Tanda tangan pribadi ditemukan: APK dibangun versi rilis."
          else
            echo "pribadi=false" >> "$GITHUB_OUTPUT"
            echo "Memakai tanda tangan bawaan GitHub: APK dibangun versi debug."
          fi

      - name: Ekstrak ZIP proyek
        run: for z in *.zip; do [ -f "$z" ] && unzip -o "$z"; done

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
          gradle-version: 9.3.1

      - name: Kompilasi APK Android
        env:
          PRIBADI: ${{ steps.tt.outputs.pribadi }}
        run: |
          ROOT_DIR=$(find . -maxdepth 4 \( -name "settings.gradle" -o -name "settings.gradle.kts" \) ! -path "*/build/*" | head -n 1)
          if [ -z "$ROOT_DIR" ]; then
            ROOT_DIR=$(find . -maxdepth 4 \( -name "build.gradle" -o -name "build.gradle.kts" \) ! -path "*/build/*" ! -path "*/app/*" | head -n 1)
          fi
          if [ -z "$ROOT_DIR" ]; then
            ROOT_DIR=$(find . -maxdepth 4 \( -name "build.gradle*" \) ! -path "*/build/*" | head -n 1)
          fi
          [ -n "$ROOT_DIR" ] && cd "$(dirname "$ROOT_DIR")"

          if [ -f "./gradlew" ]; then
            chmod +x ./gradlew
            RUN_GRADLE="./gradlew"
          else
            RUN_GRADLE="gradle"
          fi

          if [ "$PRIBADI" = "true" ]; then
            $RUN_GRADLE assembleRelease --no-daemon -x lint -x test || $RUN_GRADLE assembleDebug --no-daemon -x lint -x test
          else
            $RUN_GRADLE assembleDebug --no-daemon -x lint -x test
          fi

      - name: Tandatangani APK dengan kunci pribadi
        if: steps.tt.outputs.pribadi == 'true'
        run: |
          set -e
          KS="$GITHUB_WORKSPACE/.tanda-tangan/kunci.p12"
          PROP="$GITHUB_WORKSPACE/.tanda-tangan/sandi.properties"
          export KS_ALIAS=$(grep '^alias=' "$PROP" | head -n 1 | cut -d= -f2- | tr -d '\r')
          export KS_PASS=$(grep '^sandi=' "$PROP" | head -n 1 | cut -d= -f2- | tr -d '\r')
          BT=$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -n 1)
          APKS=$(find . -path "*/build/outputs/apk/*" -name "*.apk" ! -name "*aligned*" ! -name "*idsig*")
          test -n "$APKS" || { echo "Berkas APK tidak ditemukan!"; exit 1; }
          for APK in $APKS; do
            "$BT/zipalign" -p -f 4 "$APK" "$APK.aligned"
            "$BT/apksigner" sign --ks "$KS" --ks-type PKCS12 --ks-key-alias "$KS_ALIAS" --ks-pass env:KS_PASS --key-pass env:KS_PASS --out "$APK" "$APK.aligned"
            rm -f "$APK.aligned" "$APK.idsig"
          done
          FIRST=$(echo "$APKS" | head -n 1)
          "$BT/apksigner" verify --print-certs "$FIRST"

      - name: Siapkan berkas APK
        env:
          PRIBADI: ${{ steps.tt.outputs.pribadi }}
        run: |
          # Urutan dibuat tetap (sort) supaya varian yang dipilih selalu sama di setiap pembangunan.
          APK_PATH=""
          if [ "$PRIBADI" = "true" ]; then
            APK_PATH=$(find . \( -path "*/build/outputs/apk/release/*" -o -path "*/build/outputs/apk/*/release/*" \) -name "*.apk" | sort | head -n 1)
          fi
          if [ -z "$APK_PATH" ]; then
            APK_PATH=$(find . -path "*/build/outputs/apk/*" -name "*.apk" | sort | head -n 1)
          fi
          test -n "$APK_PATH" || { echo "Berkas APK tidak ditemukan!"; exit 1; }
          cp "$APK_PATH" "@@NAMA_APK@@-v${{ github.run_number }}.apk"

      - name: Simpan Artefak APK
        uses: actions/upload-artifact@v4
        with:
          name: APK-@@NAMA_APK@@-${{ github.run_number }}
          path: "@@NAMA_APK@@-v${{ github.run_number }}.apk"

      - name: Terbitkan ke GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: v${{ github.run_number }}
          name: Versi v${{ github.run_number }}
          generate_release_notes: false
          files: "@@NAMA_APK@@-v${{ github.run_number }}.apk"
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
    local gradleVersion = o.gradleVersion or "9.3.1"
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
    local okSusun, berkas = pcall(function() return PembuatAPK.susunBerkas(o) end)
    if not okSusun then
        PembuatAPK.tampilError("Gagal menyusun berkas proyek", tostring(berkas),
            function() PembuatAPK.formAplikasiBaru(token) end)
        return
    end
    -- Berkas workflow diunggah paling akhir agar hanya satu pembangunan yang terpicu.
    for i = 1, #berkas do
        if tostring(berkas[i].path):sub(1, 8) == ".github/" then
            table.insert(berkas, table.remove(berkas, i))
            break
        end
    end
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
            local tampilkanSukses
            tampilkanSukses = function()
                PembuatAPK.dialogTombol("Proyek berhasil dibuat", info, {
                    {"mulai pembangunan APK", function() TandaTangan.mulai(fullName, token, tampilkanSukses) end},
                    {"cek status pembangunan", function() PembuatAPK.cekStatus(fullName, token, tampilkanSukses) end},
                    {"kelola aplikasi ini", function() PembuatAPK.menuAplikasi(fullName, token) end},
                    {"buka di GitHub", function() bukaBrowser(htmlUrl) end, tetap = true},
                }, {"kembali", function() PembuatAPK.menu(token) end})
            end
            tampilkanSukses()
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
    lab("Pilihan tanda tangan APK (pribadi atau bawaan GitHub) akan ditentukan langsung saat menekan tombol Mulai pembangunan APK.")

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
            javaVersion="17",gradleVersion="9.3.1",mediaGesture=media.isChecked()})
    end})
    b.setNegativeButton("kembali",DialogInterface.OnClickListener{onClick=function() PembuatAPK.menu(token) end})
    local d=b.create(); d.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY); d.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE); d.show(); aturTombolHurufKecil(d,"buat proyek","kembali",nil)
end

local function tetapkanKembali(fullName, token, kb)
    if kb then return kb end
    return function() PembuatAPK.menuAplikasi(fullName, token) end
end

-- Dialog dengan teks yang bisa dipilih dan daftar tombol (jumlah tombol bebas).
-- tombol: {{"label", fungsi, tetap=true}, ...}  (tetap=true: dialog tidak ditutup setelah ditekan)
-- kembali: {"label", fungsi} untuk tombol bawah
function PembuatAPK.dialogTombol(judul, pesan, tombol, kembali, opsi)
    opsi = opsi or {}
    local layout = LinearLayout(service)
    layout.setOrientation(LinearLayout.VERTICAL)
    layout.setPadding(32, 16, 32, 16)

    if pesan and tostring(pesan) ~= "" then
        local tv = TextView(service)
        tv.setText(tostring(pesan))
        tv.setTextSize(opsi.ukuranTeks or 15)
        tv.setTextIsSelectable(true)
        layout.addView(tv)
    end

    local diag
    for _, t in ipairs(tombol or {}) do
        local btn = Button(service)
        btn.setText(t[1])
        pcall(function() btn.setAllCaps(false) end)
        btn.setOnClickListener(View.OnClickListener{
            onClick = function()
                if not t.tetap then pcall(function() diag.dismiss() end) end
                if t[2] then t[2]() end
            end
        })
        layout.addView(btn)
    end

    local scroll = ScrollView(service.getApplicationContext())
    scroll.setFillViewport(true)
    scroll.addView(layout)

    local b = AlertDialog.Builder(service)
    b.setTitle(judul)
    b.setView(scroll)
    if kembali then
        b.setNegativeButton(kembali[1], DialogInterface.OnClickListener{
            onClick = function() if kembali[2] then kembali[2]() end end
        })
    end
    diag = b.create()
    diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    diag.show()
    if kembali then aturTombolHurufKecil(diag, nil, kembali[1], nil) end
    return diag
end

-- Dialog error: rincian bisa dipilih dan ada tombol "salin keterangan error".
function PembuatAPK.tampilError(judul, rincian, kembaliFn, tombolTambahan)
    local teks = tostring(rincian or "Tidak ada keterangan error.")
    local tombol = {
        {"salin keterangan error", function() salinKeClipboard("Keterangan error", teks) end, tetap = true}
    }
    for _, t in ipairs(tombolTambahan or {}) do table.insert(tombol, t) end
    if service.speak then service.speak(judul .. ". Rincian error ditampilkan, ada tombol salin.") end
    PembuatAPK.dialogTombol(judul, teks, tombol, {"kembali", kembaliFn})
end

function PembuatAPK.ambilIdRunTerakhir(fullName, token, cb)
    local endpoint = "https://api.github.com/repos/" .. fullName .. "/actions/runs?per_page=1"
    kirimPermintaanGitHub("GET", endpoint, token, nil, function(ok, res)
        local id = 0
        if ok then
            pcall(function()
                local arr = JSONObject(res).optJSONArray("workflow_runs")
                if arr ~= nil and arr.length() > 0 then
                    id = arr.getJSONObject(0).optLong("id", 0)
                end
            end)
        end
        cb(id)
    end, true)
end

-- Dialog setelah berkas dari HP berhasil diunggah ke repo
function PembuatAPK.setelahUnggah(fullName, token, repoObj, pathSekarang, namaDiRepo, rawUrl, htmlUrl, diperbarui, folderRepo)
    local kembaliRepo = function()
        if folderRepo then
            bukaDirektoriRepoDialog(fullName, folderRepo, token, repoObj)
        else
            kelolaRepoPilihanDialog(repoObj, token)
        end
    end
    local idAwal = PembuatAPK.baselineRun[fullName] or 0
    local pesan = "Berkas: " .. namaDiRepo .. "\nRepo: " .. fullName
    if diperbarui then pesan = pesan .. "\n(berkas lama dengan nama sama sudah diganti)" end
    pesan = pesan .. "\n\nJika proyek sudah lengkap, tekan Bangun APK sekarang. Jika repo ini membangun APK otomatis setiap ada perubahan, tekan Pantau pembangunan APK."
    if service.speak then service.speak("Berkas berhasil diunggah.") end
    PembuatAPK.dialogTombol("Berkas berhasil diunggah", pesan, {
        {"bangun APK sekarang", function() TandaTangan.mulai(fullName, token, kembaliRepo) end},
        {"pantau pembangunan APK", function() PembuatAPK.pantau(fullName, token, kembaliRepo, idAwal) end},
        {"cek status APK", function() PembuatAPK.cekStatus(fullName, token, kembaliRepo) end},
        {"unggah berkas lain", function() unggahDariMemoriHPDialog(fullName, token, repoObj, pathSekarang, folderRepo) end},
        {"salin tautan raw", function() salinKeClipboard("Tautan raw", rawUrl) end, tetap = true},
        {"bagikan tautan", function() bagikanTautan("Berkas: " .. namaDiRepo, rawUrl ~= "" and rawUrl or htmlUrl) end, tetap = true},
    }, {"kembali", kembaliRepo})
end

-- Tampilkan hasil satu proses pembangunan (berhasil / gagal / berjalan)
function PembuatAPK.tampilkanHasilRun(fullName, token, run, kembali)
    local status = run.optString("status", "")
    local kesimpulan = run.optString("conclusion", "")
    local teksStatus = terjemahStatus(status, kesimpulan)
    local logUrl = run.optString("html_url", "")
    local runId = run.optLong("id", 0)
    local nomor = run.optInt("run_number", 0)
    local judulRun = run.optString("display_title", run.optString("name", ""))

    local pesan = "Proyek: " .. fullName .. "\nPembangunan nomor: " .. tostring(nomor)
    if judulRun ~= "" then pesan = pesan .. "\nKeterangan: " .. judulRun end
    pesan = pesan .. "\nStatus: " .. teksStatus

    local ulang = function() TandaTangan.mulai(fullName, token, kembali) end
    local web = function() bukaBrowser(logUrl) end

    if status == "completed" and kesimpulan == "success" then
        pesan = pesan .. "\n\nAPK sudah selesai dan rilisnya siap diunduh."
        PembuatAPK.dialogTombol("Pembangunan APK berhasil", pesan, {
            {"unduh APK", function() PembuatAPK.ambilAPK(fullName, token, kembali) end},
            {"bangun ulang", ulang},
            {"buka halaman proses di web", web},
        }, {"kembali", kembali})
    elseif status == "completed" then
        pesan = pesan .. "\n\nPembangunan tidak berhasil. Tekan Rincian error untuk melihat penyebabnya, lalu tekan salin bila perlu."
        PembuatAPK.dialogTombol("Pembangunan APK gagal", pesan, {
            {"rincian error", function() PembuatAPK.bacaLogError(fullName, token, runId, logUrl, kembali) end},
            {"bangun ulang", ulang},
            {"buka log di web", web},
        }, {"kembali", kembali})
    else
        pesan = pesan .. "\n\nPembangunan masih berjalan."
        PembuatAPK.dialogTombol("Pembangunan sedang berjalan", pesan, {
            {"pantau otomatis", function() PembuatAPK.pantau(fullName, token, kembali, 0) end},
            {"periksa lagi", function() PembuatAPK.cekStatus(fullName, token, kembali) end},
            {"buka di web", web},
        }, {"kembali", kembali})
    end
    if service.speak then service.speak("Status pembangunan: " .. teksStatus) end
end

-- Pantau otomatis sampai pembangunan selesai, lalu hasilnya muncul sendiri
function PembuatAPK.pantau(fullName, token, kb, idAwal)
    local kembali = tetapkanKembali(fullName, token, kb)
    idAwal = idAwal or 0
    local aktif = true
    local mulai = os.time()
    local statusTerakhir = ""
    local gagalBeruntun = 0
    local JEDA_MS = 10000
    local MAKS_TUNGGU_MUNCUL = 120
    local MAKS_TOTAL = 2700
    local endpoint = "https://api.github.com/repos/" .. fullName .. "/actions/runs?per_page=1"

    local layout = LinearLayout(service)
    layout.setOrientation(LinearLayout.VERTICAL)
    layout.setPadding(32, 24, 32, 16)
    local tv = TextView(service)
    tv.setTextSize(15)
    tv.setText("Menunggu GitHub memulai pembangunan APK...")
    layout.addView(tv)

    local diag
    local b = AlertDialog.Builder(service)
    b.setTitle("Memantau pembangunan APK")
    b.setView(layout)
    b.setNeutralButton("lihat status", DialogInterface.OnClickListener{
        onClick = function()
            aktif = false
            PembuatAPK.cekStatus(fullName, token, kembali)
        end
    })
    b.setNegativeButton("berhenti memantau", DialogInterface.OnClickListener{
        onClick = function()
            aktif = false
            kembali()
        end
    })
    b.setOnDismissListener(DialogInterface.OnDismissListener{
        onDismiss = function() aktif = false end
    })
    diag = b.create()
    diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    layarTetapMenyala(diag)
    diag.show()
    aturTombolHurufKecil(diag, nil, "berhenti memantau", "lihat status")
    if service.speak then service.speak("Memantau pembangunan APK. Hasilnya akan muncul otomatis.") end

    local tick
    local function jadwalkan()
        mainHandler.postDelayed(Runnable{ run = function() tick() end }, JEDA_MS)
    end

    tick = function()
        if not aktif then return end
        if os.time() - mulai > MAKS_TOTAL then
            aktif = false
            pcall(function() diag.dismiss() end)
            PembuatAPK.tampilError("Pemantauan dihentikan",
                "Pemantauan sudah lebih dari 45 menit tanpa hasil.\nProyek: " .. fullName,
                kembali,
                {{"periksa status", function() PembuatAPK.cekStatus(fullName, token, kembali) end}})
            return
        end
        kirimPermintaanGitHub("GET", endpoint, token, nil, function(ok, res)
            if not aktif then return end
            local run = nil
            if ok then
                gagalBeruntun = 0
                pcall(function()
                    local arr = JSONObject(res).optJSONArray("workflow_runs")
                    if arr ~= nil and arr.length() > 0 then run = arr.getJSONObject(0) end
                end)
            else
                gagalBeruntun = gagalBeruntun + 1
                if gagalBeruntun >= 5 then
                    aktif = false
                    pcall(function() diag.dismiss() end)
                    PembuatAPK.tampilError("Gagal memantau pembangunan",
                        "Proyek: " .. fullName .. "\n\n" .. tostring(res), kembali,
                        {{"pantau lagi", function() PembuatAPK.pantau(fullName, token, kembali, idAwal) end}})
                    return
                end
            end

            local lewat = os.time() - mulai
            if run ~= nil and run.optLong("id", 0) > idAwal then
                local status = run.optString("status", "")
                if status == "completed" then
                    aktif = false
                    pcall(function() diag.dismiss() end)
                    PembuatAPK.tampilkanHasilRun(fullName, token, run, kembali)
                    return
                end
                local teksStatus = terjemahStatus(status, "")
                tv.setText("Status: " .. teksStatus .. "\nWaktu pemantauan: " ..
                    math.floor(lewat / 60) .. " menit " .. (lewat % 60) .. " detik\n\nHasil akan muncul otomatis saat pembangunan selesai.")
                if status ~= statusTerakhir then
                    statusTerakhir = status
                    if service.speak then service.speak("Status pembangunan: " .. teksStatus) end
                end
            elseif lewat > MAKS_TUNGGU_MUNCUL then
                aktif = false
                pcall(function() diag.dismiss() end)
                PembuatAPK.dialogTombol("Belum ada pembangunan baru",
                    "GitHub belum memulai pembangunan APK baru di repo ini. Kemungkinan repo tidak membangun otomatis saat berkas diunggah.\n\nTekan Bangun APK sekarang untuk memulai secara manual.",
                    {
                        {"bangun APK sekarang", function() TandaTangan.mulai(fullName, token, kembali) end},
                        {"lihat status terakhir", function() PembuatAPK.cekStatus(fullName, token, kembali) end},
                    }, {"kembali", kembali})
                return
            else
                tv.setText("Menunggu GitHub memulai pembangunan... (" .. lewat .. " detik)")
            end
            jadwalkan()
        end, true)
    end

    tick()
end

-- ===== Analisis log build (mulai v1.17) =====
-- Setiap item: {kata kunci huruf kecil (dicari apa adanya), penjelasan dalam bahasa Indonesia}
PembuatAPK.DAFTAR_PENYEBAB = {
    {"unresolved reference", "Ada nama (kelas, fungsi, variabel, atau sumber daya R.xxx) yang dipakai kode tetapi tidak ditemukan. Penyebab umum: salah ketik, lupa import, pustaka belum terpasang, atau sumber daya belum dibuat di folder res."},
    {"type mismatch", "Tipe data tidak cocok: nilai yang diberikan bukan tipe yang diminta oleh fungsi atau variabel."},
    {"overrides nothing", "Fungsi bertanda override tidak ada di kelas induknya. Nama atau parameternya berbeda dengan yang dimiliki versi Android atau pustaka yang dipakai."},
    {"overload resolution ambiguity", "Pemanggilan fungsi ambigu: ada beberapa fungsi yang cocok sehingga kompiler tidak bisa memilih."},
    {"none of the following candidates", "Pemanggilan fungsi tidak cocok dengan parameter yang tersedia (jumlah atau tipe parameter salah)."},
    {"must be exhaustive", "Ekspresi when atau if dipakai sebagai nilai tetapi tidak menutup semua kemungkinan. Tambahkan cabang else."},
    {"val cannot be reassigned", "Nilai bertanda val diubah setelah diisi. Ganti val menjadi var."},
    {"expecting '", "Penulisan kode salah: kurang atau berlebih tanda kurung, koma, atau kata kunci."},
    {"cannot find symbol", "Kode Java memakai nama yang tidak ditemukan (kelas, fungsi, atau variabel)."},
    {"was compiled with an incompatible version of kotlin", "Ada pustaka yang dibuat dengan versi Kotlin lebih baru daripada yang dipakai proyek. Naikkan versi plugin Kotlin atau pakai versi pustaka yang lebih lama."},
    {"could not resolve", "Pustaka atau plugin tidak bisa diunduh. Nama atau versinya salah, atau alamat repositori (google, mavenCentral, jitpack) belum didaftarkan di settings.gradle."},
    {"could not find ", "Pustaka, plugin, atau berkas yang diminta tidak ditemukan. Periksa nama, versi, dan daftar repositori."},
    {"failed to find target with hash string", "Platform Android untuk compileSdk belum terpasang di mesin GitHub. Pasang platform itu di langkah SDK, atau turunkan compileSdk."},
    {"licenses have not been accepted", "Lisensi paket Android SDK belum diterima, jadi paket yang dibutuhkan tidak bisa dipasang otomatis."},
    {"failed to install the following", "Paket Android SDK yang dibutuhkan gagal dipasang otomatis (biasanya karena lisensi belum diterima atau nama paket salah)."},
    {"sdk location not found", "Lokasi Android SDK tidak diketahui oleh Gradle. Langkah pemasangan SDK mungkin gagal."},
    {"java heap space", "Memori Java kehabisan saat membangun. Naikkan nilai org.gradle.jvmargs di gradle.properties."},
    {"outofmemoryerror", "Memori kehabisan saat membangun. Naikkan nilai org.gradle.jvmargs di gradle.properties."},
    {"unsupported class file major version", "Versi Java tidak cocok dengan Gradle atau pustaka yang dipakai. Pastikan versi Java di workflow sesuai kebutuhan proyek."},
    {"invalid source release", "Versi Java di workflow lebih rendah dari yang diminta proyek. Naikkan versi Java di langkah pemasangan Java."},
    {"inconsistent jvm-target", "Target JVM Java dan Kotlin berbeda. Samakan sourceCompatibility, targetCompatibility, dan jvmTarget."},
    {"duplicate class", "Ada kelas ganda: dua pustaka berisi kelas yang sama. Hapus salah satu pustaka atau kecualikan salah satunya."},
    {"manifest merger failed", "Penggabungan AndroidManifest.xml gagal. Baca pesan di atasnya untuk melihat atribut atau komponen yang bermasalah."},
    {"android:exported", "Komponen di AndroidManifest.xml (activity, service, receiver) yang punya intent-filter wajib memakai android:exported untuk target SDK 31 ke atas."},
    {"linking references failed", "Ada sumber daya (string, gaya, gambar) yang dirujuk tetapi tidak ada atau salah tulis di folder res atau AndroidManifest.xml."},
    {"error: resource", "Ada sumber daya yang dirujuk tetapi tidak ditemukan. Periksa nama dan folder res."},
    {"minsdkversion", "minSdk proyek lebih kecil dari yang dibutuhkan salah satu pustaka. Naikkan minSdk atau pakai pustaka versi lama."},
    {"minimum supported gradle version", "Versi Gradle terlalu rendah untuk plugin Android (AGP). Naikkan gradle-version di workflow."},
    {"script compilation error", "Berkas build.gradle atau settings.gradle salah tulis. Baca baris yang disebut di pesan."},
    {"could not get unknown property", "Berkas build.gradle memakai properti yang tidak dikenal. Periksa ejaan atau versi plugin."},
    {"no signature of method", "Berkas build.gradle memanggil fungsi yang tidak ada di versi Gradle atau plugin ini."},
    {"end-of-central-directory", "Berkas ZIP proyek rusak atau tidak lengkap saat diekstrak. Unggah ulang ZIP-nya."},
    {"does not contain a gradle build", "Gradle tidak menemukan settings.gradle atau build.gradle di folder proyek. Periksa struktur folder di repo."},
    {"berkas apk tidak ditemukan", "Pembangunan selesai tetapi tidak menghasilkan berkas APK. Periksa tugas assembleDebug dan jalur keluaran."},
    {"permission denied", "Ada berkas yang tidak boleh dijalankan atau dibaca (misalnya gradlew tanpa izin eksekusi)."},
}

-- Membersihkan satu baris log: buang cap waktu, kode warna, dan karakter CR.
PembuatAPK.bersihkanBarisLog = function(b)
    local c = tostring(b)
    c = c:gsub("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d%.%d+Z%s?", "")
    c = c:gsub("\27%[[%d;]*[A-Za-z]", "")
    c = c:gsub("\r", "")
    return c
end

PembuatAPK.pangkasTeks = function(s)
    s = tostring(s)
    s = s:gsub("^%s+", "")
    s = s:gsub("%s+$", "")
    return s
end

-- Memendekkan jalur berkas di mesin GitHub menjadi jalur relatif di dalam repo.
PembuatAPK.pendekkanJalur = function(p)
    p = tostring(p)
    p = p:gsub("^file:///", "/")
    p = p:gsub("^/?home/runner/work/[^/]+/[^/]+/", "")
    return p
end

PembuatAPK.formatGalatKode = function(g)
    local lokasi = ""
    if g.berkas then
        lokasi = g.berkas
        if g.baris then lokasi = lokasi .. " baris " .. tostring(g.baris) end
        if g.kolom then lokasi = lokasi .. " kolom " .. tostring(g.kolom) end
        lokasi = lokasi .. ": "
    end
    return "[" .. g.tipe .. "] " .. lokasi .. g.pesan
end

-- Menganalisis log mentah (tabel baris) dan mengembalikan tabel hasil.
PembuatAPK.analisisLog = function(mentah)
    local b = {}
    for i = 1, #mentah do b[i] = PembuatAPK.bersihkanBarisLog(mentah[i]) end

    -- Cari awal dan akhir langkah yang gagal: dari "##[group]Run" terakhir sebelum "##[error]" pertama.
    local idxGalat = nil
    for i = 1, #b do
        if b[i]:find("^##%[error%]") then
            idxGalat = i
            break
        end
    end
    local mulai = 1
    if idxGalat then
        for i = idxGalat, 1, -1 do
            if b[i]:find("^##%[group%]Run ") then
                mulai = i
                break
            end
        end
    end
    local akhir = idxGalat or #b
    local wilayah = {}
    for i = mulai, akhir do wilayah[#wilayah + 1] = b[i] end

    local hasil = {
        bersih = b,
        wilayah = wilayah,
        wilayahDitemukan = (idxGalat ~= nil),
        tugas = nil,
        galatKode = {},
        galatLain = {},
        blokGradle = {},
        penyebab = {},
    }

    local terlihat = {}
    local kataLain = {
        "could not resolve", "could not find ", "caused by:", "duplicate class",
        "manifest merger failed", "license for package", "sdk location not found",
        "failed to install", "outofmemoryerror", "java heap space", "unsupported class file",
        "invalid source release", "no such file", "permission denied", "script compilation error",
        "could not get unknown property", "execution failed", "failed to find", "cannot find",
        "berkas apk tidak ditemukan", "error:", "unzip:", "end-of-central-directory",
    }

    local n = #wilayah
    local i = 1
    while i <= n do
        local l = wilayah[i]
        local lower = l:lower()

        local rest = l:match("^e: (.*)$")
        if rest then
            local f, ln, kol, ps = rest:match("^file:///(.-%.kts?):(%d+):(%d+)%s+(.*)$")
            if not f then f, ln, kol, ps = rest:match("^file:///(.-%.kts?):%((%d+), (%d+)%):%s*(.*)$") end
            if not f then f, ln, kol, ps = rest:match("^(.-%.kts?):%((%d+), (%d+)%):%s*(.*)$") end
            local item
            if f then
                item = {tipe = "Kotlin", berkas = PembuatAPK.pendekkanJalur(f), baris = tonumber(ln), kolom = tonumber(kol), pesan = ps}
            else
                item = {tipe = "Kotlin", pesan = PembuatAPK.pangkasTeks(rest)}
            end
            local kunci = tostring(item.berkas) .. "|" .. tostring(item.baris) .. "|" .. tostring(item.kolom) .. "|" .. item.pesan
            if not terlihat[kunci] and #hasil.galatKode < 300 then
                terlihat[kunci] = true
                hasil.galatKode[#hasil.galatKode + 1] = item
            end
        else
            local jf, jl, jp = l:match("^(%S+%.java):(%d+): error: (.*)$")
            if jf then
                local pesan = jp
                local s1 = wilayah[i + 1]
                local s2 = wilayah[i + 2]
                if s1 and s1 ~= "" and not s1:find("^%S+%.java:%d+:") then
                    pesan = pesan .. "  |  " .. PembuatAPK.pangkasTeks(s1)
                    if s2 and s2:find("^%s*%^") then i = i + 1 end
                    i = i + 1
                end
                local item = {tipe = "Java", berkas = PembuatAPK.pendekkanJalur(jf), baris = tonumber(jl), pesan = pesan}
                local kunci = tostring(item.berkas) .. "|" .. tostring(item.baris) .. "|" .. item.pesan
                if not terlihat[kunci] and #hasil.galatKode < 300 then
                    terlihat[kunci] = true
                    hasil.galatKode[#hasil.galatKode + 1] = item
                end
            else
                local tugas = l:match("^> Task (%S+) FAILED")
                if tugas then hasil.tugas = tugas end
                local tugas2 = l:match("Execution failed for task '([^']+)'")
                if tugas2 and not hasil.tugas then hasil.tugas = tugas2 end

                if l:find("* What went wrong:", 1, true) then
                    local k = i + 1
                    local dihitung = 0
                    while k <= n and dihitung < 25 do
                        local x = wilayah[k]
                        if x:find("^%* Try:") or x:find("^%* Exception") or x:find("^%* Get more help") then break end
                        if PembuatAPK.pangkasTeks(x) ~= "" then
                            hasil.blokGradle[#hasil.blokGradle + 1] = x
                            dihitung = dihitung + 1
                        end
                        k = k + 1
                    end
                elseif not l:find("^##%[error%]Process completed") and not l:find("^w: ") then
                    for _, kata in ipairs(kataLain) do
                        if lower:find(kata, 1, true) then
                            local teks = PembuatAPK.pendekkanJalur(PembuatAPK.pangkasTeks(l))
                            if teks ~= "" and not terlihat["L|" .. teks] and #hasil.galatLain < 60 then
                                terlihat["L|" .. teks] = true
                                hasil.galatLain[#hasil.galatLain + 1] = teks
                            end
                            break
                        end
                    end
                end
            end
        end
        i = i + 1
    end

    -- Buang baris "lain" yang sudah tampil di blok pesan Gradle.
    local dalamBlok = {}
    for _, x in ipairs(hasil.blokGradle) do dalamBlok[PembuatAPK.pangkasTeks(x)] = true end
    local sisa = {}
    for _, x in ipairs(hasil.galatLain) do
        if not dalamBlok[x] then sisa[#sisa + 1] = x end
    end
    hasil.galatLain = sisa

    -- Penjelasan penyebab berdasarkan isi langkah yang gagal.
    local teksKecil = table.concat(wilayah, "\n"):lower()
    local sudahJelas = {}
    for _, p in ipairs(PembuatAPK.DAFTAR_PENYEBAB) do
        if teksKecil:find(p[1], 1, true) and not sudahJelas[p[2]] and #hasil.penyebab < 6 then
            sudahJelas[p[2]] = true
            hasil.penyebab[#hasil.penyebab + 1] = p[2]
        end
    end

    return hasil
end

-- Menyusun teks laporan. batas = jumlah maksimum kesalahan kode yang ditampilkan (nil = semua).
PembuatAPK.susunTeksAnalisis = function(a, header, batas)
    local t = {}
    t[#t + 1] = header
    t[#t + 1] = ""
    if a.tugas then t[#t + 1] = "Tugas Gradle yang gagal: " .. a.tugas end
    t[#t + 1] = "Jumlah kesalahan kode: " .. tostring(#a.galatKode)

    if #a.galatKode > 0 then
        t[#t + 1] = ""
        t[#t + 1] = "PENYEBAB UTAMA (kesalahan di kode)"
        local tampil = #a.galatKode
        if batas and tampil > batas then tampil = batas end
        for k = 1, tampil do
            t[#t + 1] = tostring(k) .. ". " .. PembuatAPK.formatGalatKode(a.galatKode[k])
        end
        if tampil < #a.galatKode then
            t[#t + 1] = "(Hanya " .. tostring(tampil) .. " dari " .. tostring(#a.galatKode) .. " kesalahan yang ditampilkan di sini. Tekan \"salin semua kesalahan\" untuk daftar lengkap.)"
        end
    end

    if #a.penyebab > 0 then
        t[#t + 1] = ""
        t[#t + 1] = "ARTINYA"
        for _, p in ipairs(a.penyebab) do t[#t + 1] = "- " .. p end
    end

    if #a.blokGradle > 0 then
        t[#t + 1] = ""
        t[#t + 1] = "PESAN DARI GRADLE"
        for _, x in ipairs(a.blokGradle) do t[#t + 1] = x end
    end

    if #a.galatLain > 0 then
        t[#t + 1] = ""
        t[#t + 1] = "BARIS KESALAHAN LAIN DI LOG"
        local maks = #a.galatLain
        if batas and maks > 12 then maks = 12 end
        for k = 1, maks do t[#t + 1] = "- " .. a.galatLain[k] end
        if maks < #a.galatLain then
            t[#t + 1] = "(" .. tostring(#a.galatLain - maks) .. " baris lain ada di \"salin semua kesalahan\".)"
        end
    end

    local adaTemuan = (#a.galatKode > 0) or (#a.galatLain > 0) or (#a.blokGradle > 0)
    local jumlahAkhir = adaTemuan and 12 or 40
    t[#t + 1] = ""
    if adaTemuan then
        t[#t + 1] = "BARIS TERAKHIR LANGKAH YANG GAGAL"
    else
        t[#t + 1] = "Tidak ada baris kesalahan yang dikenali otomatis. Berikut " .. tostring(jumlahAkhir) .. " baris terakhir langkah yang gagal:"
    end
    local w = a.wilayah
    local kumpul = {}
    for k = #w, 1, -1 do
        if PembuatAPK.pangkasTeks(w[k]) ~= "" then
            table.insert(kumpul, 1, w[k])
            if #kumpul >= jumlahAkhir then break end
        end
    end
    for _, x in ipairs(kumpul) do t[#t + 1] = x end

    return table.concat(t, "\n")
end

-- Kalimat singkat untuk dibacakan pembaca layar.
PembuatAPK.kalimatBicara = function(a, namaLangkah)
    local s = "Langkah gagal: " .. tostring(namaLangkah) .. ". "
    if #a.galatKode > 0 then
        local g = a.galatKode[1]
        s = s .. "Ditemukan " .. tostring(#a.galatKode) .. " kesalahan kode. Yang pertama: "
        if g.berkas then
            s = s .. "berkas " .. g.berkas
            if g.baris then s = s .. " baris " .. tostring(g.baris) end
            s = s .. ". "
        end
        s = s .. (g.pesan:gsub("%.+$", "")) .. ". "
    elseif #a.penyebab > 0 then
        s = s .. a.penyebab[1] .. " "
    elseif #a.galatLain > 0 then
        s = s .. "Pesan: " .. a.galatLain[1] .. ". "
    else
        s = s .. "Penyebab tidak dikenali otomatis. Log langkah gagal ditampilkan. "
    end
    s = s .. "Rincian lengkap ditampilkan, ada tombol salin."
    return s
end

function PembuatAPK.bacaLogError(fullName, token, runId, logUrl, kb)
    local kembali = tetapkanKembali(fullName, token, kb)
    local progress = ProgressDialog(service)
    progress.setTitle("Menganalisis Error")
    progress.setMessage("Mengambil rincian kegagalan build...")
    progress.setCancelable(true)
    progress.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    progress.show()

    local bukaWeb = {{"buka log di web", function() bukaBrowser(logUrl) end}}
    local endpointJobs = "https://api.github.com/repos/" .. fullName .. "/actions/runs/" .. tostring(runId) .. "/jobs"
    kirimPermintaanGitHub("GET", endpointJobs, token, nil, function(okJobs, resJobs)
        if not okJobs then
            pcall(function() progress.dismiss() end)
            PembuatAPK.tampilError("Gagal memeriksa rincian build",
                "Proyek: " .. fullName .. "\nRun ID: " .. tostring(runId) .. "\n\n" .. tostring(resJobs),
                kembali, bukaWeb)
            return
        end

        local targetJobId = nil
        local namaJob = "Tidak diketahui"
        local namaLangkahGagal = "Tidak diketahui"

        pcall(function()
            local jobsArr = JSONObject(resJobs).optJSONArray("jobs")
            if jobsArr ~= nil then
                for i = 0, jobsArr.length() - 1 do
                    local j = jobsArr.getJSONObject(i)
                    local kes = j.optString("conclusion", "")
                    if kes == "failure" or kes == "timed_out" or kes == "cancelled" then
                        targetJobId = j.optLong("id", 0)
                        namaJob = j.optString("name", namaJob)
                        local stepsArr = j.optJSONArray("steps")
                        if stepsArr ~= nil then
                            for k = 0, stepsArr.length() - 1 do
                                local st = stepsArr.getJSONObject(k)
                                local ks = st.optString("conclusion", "")
                                if ks == "failure" or ks == "timed_out" or ks == "cancelled" then
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
            PembuatAPK.tampilError("Rincian Error",
                "Proyek: " .. fullName .. "\nRun ID: " .. tostring(runId) ..
                "\n\nTidak ditemukan langkah yang gagal. Kemungkinan berkas alur kerja (.github/workflows) salah tulis sehingga proses tidak bisa dimulai, atau proses dibatalkan.\n\nBuka log di web untuk melihat pesan dari GitHub:\n" .. tostring(logUrl),
                kembali, bukaWeb)
            return
        end

        pcall(function() progress.setMessage("Mengunduh teks log dari GitHub...") end)

        local header = "Proyek: " .. fullName .. "\nRun ID: " .. tostring(runId) ..
            "\nJob: " .. namaJob .. "\nLangkah gagal: " .. namaLangkahGagal

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
                    if code == 301 or code == 302 or code == 303 or code == 307 or code == 308 then
                        local redir = conn.getHeaderField("Location")
                        conn.disconnect()
                        url = URL(redir)
                        conn = url.openConnection()
                        conn.setRequestMethod("GET")
                        conn.setRequestProperty("User-Agent", "Android-Accessibility-Manager")
                        conn.setConnectTimeout(15000)
                        conn.setReadTimeout(30000)
                    elseif code >= 400 then
                        error("Kode " .. tostring(code) .. " saat mengambil log (log mungkin sudah kedaluwarsa atau token tidak punya izin).")
                    end

                    local is = conn.getInputStream()
                    local reader = BufferedReader(InputStreamReader(is, "UTF-8"))
                    local barisLog = {}
                    local l = reader.readLine()
                    while l ~= nil do
                        barisLog[#barisLog + 1] = tostring(l)
                        if #barisLog > 40000 then
                            -- Log sangat besar: buang bagian paling awal, bagian akhir yang berisi kegagalan dipertahankan.
                            local baru = {}
                            for q = 10001, #barisLog do baru[#baru + 1] = barisLog[q] end
                            barisLog = baru
                        end
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
                            PembuatAPK.tampilError("Gagal Mengambil Log",
                                header .. "\n\nTidak dapat membaca berkas log:\n" .. tostring(hasilLog),
                                kembali, bukaWeb)
                            return
                        end

                        local okA, a = pcall(PembuatAPK.analisisLog, hasilLog)
                        local teksRingkas, teksSemua, teksLangkah, teksAkhir, bicara

                        local function ambilAkhir(tabel, jumlah)
                            local keluar = {}
                            for q = math.max(1, #tabel - jumlah + 1), #tabel do
                                keluar[#keluar + 1] = PembuatAPK.bersihkanBarisLog(tabel[q])
                            end
                            return table.concat(keluar, "\n")
                        end

                        if okA and a then
                            teksRingkas = PembuatAPK.susunTeksAnalisis(a, header, 20)
                            teksSemua = PembuatAPK.susunTeksAnalisis(a, header, nil)
                            teksLangkah = header .. "\n\n--- Log langkah yang gagal ---\n" .. ambilAkhir(a.wilayah, 1500)
                            bicara = PembuatAPK.kalimatBicara(a, namaLangkahGagal)
                        else
                            teksRingkas = header .. "\n\nAnalisis otomatis gagal: " .. tostring(a) ..
                                "\n\n--- 60 baris terakhir log ---\n" .. ambilAkhir(hasilLog, 60)
                            teksSemua = teksRingkas
                            teksLangkah = teksRingkas
                            bicara = "Langkah gagal: " .. namaLangkahGagal .. ". Analisis otomatis gagal, 60 baris terakhir log ditampilkan."
                        end
                        teksAkhir = header .. "\n\n--- Log (600 baris terakhir) ---\n" .. ambilAkhir(hasilLog, 600)

                        if service.speak then service.speak(bicara) end

                        PembuatAPK.dialogTombol("Hasil Analisis Error APK", teksRingkas, {
                            {"salin ringkasan penyebab", function() salinKeClipboard("Ringkasan penyebab error APK", teksRingkas) end, tetap = true},
                            {"salin semua kesalahan", function() salinKeClipboard("Semua kesalahan APK", teksSemua) end, tetap = true},
                            {"salin log langkah yang gagal", function() salinKeClipboard("Log langkah gagal APK", teksLangkah) end, tetap = true},
                            {"salin 600 baris terakhir log", function() salinKeClipboard("Log lengkap APK", teksAkhir) end, tetap = true},
                            {"buka log di web", function() bukaBrowser(logUrl) end},
                        }, {"kembali", kembali}, {ukuranTeks = 13})
                    end
                })
            end
        }).start()
    end, true)
end

function PembuatAPK.cekStatus(fullName, token, kb)
    local kembali = tetapkanKembali(fullName, token, kb)
    local endpoint = "https://api.github.com/repos/" .. fullName .. "/actions/runs?per_page=1"
    kirimPermintaanGitHub("GET", endpoint, token, nil, function(ok, res)
        if not ok then
            PembuatAPK.tampilError("Gagal memeriksa status",
                "Proyek: " .. fullName .. "\n\n" .. tostring(res), kembali,
                {{"coba lagi", function() PembuatAPK.cekStatus(fullName, token, kembali) end}})
            return
        end
        local run = nil
        pcall(function()
            local arr = JSONObject(res).optJSONArray("workflow_runs")
            if arr ~= nil and arr.length() > 0 then run = arr.getJSONObject(0) end
        end)
        if run == nil then
            PembuatAPK.dialogTombol("Status pembangunan",
                "Proyek: " .. fullName .. "\n\nBelum ada pembangunan APK yang tercatat di repo ini. Tekan Bangun APK sekarang untuk memulai.",
                {{"bangun APK sekarang", function() TandaTangan.mulai(fullName, token, kembali) end}},
                {"kembali", kembali})
            return
        end
        PembuatAPK.tampilkanHasilRun(fullName, token, run, kembali)
    end)
end

-- Buka daftar unduhan; bila tidak ada aplikasi yang menanganinya, beri petunjuk manual.
local function bukaFolderDownload()
    local ok = pcall(function()
        local i = Intent("android.intent.action.VIEW_DOWNLOADS")
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        service.startActivity(i)
    end)
    if not ok then
        local pesan = "Buka aplikasi File lalu folder Download."
        if service.speak then service.speak(pesan) end
        Toast.makeText(service, pesan, Toast.LENGTH_LONG).show()
    end
end

-- Android 7 ke atas menolak alamat berkas langsung (file://) saat membuka pemasang APK.
-- Larangan itu dimatikan (lewat refleksi) agar pemasang APK bisa dibuka dari berkas di folder Download.
local function izinkanAlamatBerkasLangsung()
    pcall(function()
        if Build.VERSION.SDK_INT >= 24 then
            local kelas = luajava.bindClass("java.lang.Class").forName("android.os.StrictMode")
            local metode = kelas.getMethod("disableDeathOnFileUriExposure", {})
            metode.invoke(nil, {})
        end
    end)
end

local function unduhLangsungKeFolderDownload(urlDownload, namaFileSimpan, tokenAuth, isZipArtifact, kembali, octet, urlCadangan)
    local progress = ProgressDialog(service)
    progress.setTitle("Mengunduh APK")
    progress.setMessage("Sedang mengunduh " .. namaFileSimpan .. " langsung ke folder Download...")
    progress.setCancelable(false)
    progress.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    layarTetapMenyala(progress)
    progress.show()

    if service.speak then service.speak("Mulai mengunduh berkas APK ke folder Download.") end

    Thread(Runnable{
        run = function()
            local function ambil(urlD, authD, octetD)
                local url = URL(urlD)
                local conn = url.openConnection()
                conn.setRequestMethod("GET")
                conn.setRequestProperty("User-Agent", "Android-Accessibility-Manager")
                if octetD then conn.setRequestProperty("Accept", "application/octet-stream") end
                if authD and authD ~= "" then
                    conn.setRequestProperty("Authorization", "Bearer " .. authD)
                end
                conn.setConnectTimeout(20000)
                conn.setReadTimeout(60000)

                local respCode = conn.getResponseCode()
                if respCode == 301 or respCode == 302 or respCode == 303 or respCode == 307 or respCode == 308 then
                    local redirectUrl = conn.getHeaderField("Location")
                    conn.disconnect()
                    url = URL(redirectUrl)
                    conn = url.openConnection()
                    conn.setRequestMethod("GET")
                    conn.setRequestProperty("User-Agent", "Android-Accessibility-Manager")
                    conn.setConnectTimeout(20000)
                    conn.setReadTimeout(60000)
                    respCode = conn.getResponseCode()
                end
                if respCode >= 400 then
                    error("Server menjawab kode " .. tostring(respCode) .. " untuk " .. urlD)
                end

                local downloadDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                if not downloadDir.exists() then downloadDir.mkdirs() end

                local fileFinalPath = ""
                local isStream = conn.getInputStream()

                if isZipArtifact then
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
                        error("Artefak yang dipilih bukan berkas aplikasi. Tunggu pembangunan APK selesai.")
                    end
                else
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
            end

            local ok, err = pcall(function() return ambil(urlDownload, tokenAuth, octet) end)
            if not ok and urlCadangan and urlCadangan ~= "" then
                local ok2, err2 = pcall(function() return ambil(urlCadangan, nil, false) end)
                if ok2 then
                    ok, err = true, err2
                else
                    err = tostring(err) .. "\n\nPercobaan cadangan:\n" .. tostring(err2)
                end
            end

            mainHandler.post(Runnable{
                run = function()
                    pcall(function() progress.dismiss() end)
                    if ok then
                        local jalurApk = tostring(err)
                        if service.speak then service.speak("Unduhan selesai. APK tersimpan di folder Download.") end
                        PembuatAPK.dialogTombol("APK Berhasil Disimpan",
                            "Berkas APK berhasil diunduh ke folder Download:\n\n" .. jalurApk, {
                            {"pasang APK sekarang", function()
                                izinkanAlamatBerkasLangsung()
                                local okPasang = pcall(function()
                                    local f = File(jalurApk)
                                    local intent = Intent(Intent.ACTION_VIEW)
                                    intent.setDataAndType(Uri.fromFile(f), "application/vnd.android.package-archive")
                                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    service.startActivity(intent)
                                end)
                                if not okPasang then
                                    Toast.makeText(service, "Tidak bisa membuka pemasang langsung. Membuka folder Download, pilih berkas APK di sana.", Toast.LENGTH_LONG).show()
                                    bukaFolderDownload()
                                end
                            end},
                            {"buka folder Download", function() bukaFolderDownload() end},
                            {"salin lokasi berkas", function() salinKeClipboard("Lokasi APK", jalurApk) end, tetap = true},
                        }, {"tutup", kembali})
                    else
                        PembuatAPK.tampilError("Gagal Mengunduh APK",
                            "Berkas: " .. namaFileSimpan .. "\n\nKesalahan:\n" .. tostring(err),
                            kembali,
                            {{"buka di browser", function() bukaBrowser(urlCadangan or urlDownload) end}})
                    end
                end
            })
        end
    }).start()
end

function PembuatAPK.ambilAPK(fullName, token, kb)
    local kembali = tetapkanKembali(fullName, token, kb)
    local endpointRelease = "https://api.github.com/repos/" .. fullName .. "/releases/latest"
    kirimPermintaanGitHub("GET", endpointRelease, token, nil, function(okRel, resRel)
        if okRel then
            local r = JSONObject(resRel)
            local aset = r.optJSONArray("assets")
            if aset ~= nil and aset.length() > 0 then
                local targetAset = nil
                for i = 0, aset.length() - 1 do
                    local it = aset.getJSONObject(i)
                    local nm = it.optString("name", ""):lower()
                    if nm:find("%.apk$") then
                        targetAset = it
                        break
                    end
                end
                if not targetAset then targetAset = aset.getJSONObject(0) end

                local nama = targetAset.optString("name", "aplikasi.apk")
                local ukuran = targetAset.optLong("size", 0)
                local tautan = targetAset.optString("browser_download_url", "")
                local urlApi = targetAset.optString("url", "")
                if urlApi == "" then urlApi = tautan end
                local tag = r.optString("tag_name", "")
                local tglRilis = r.optString("published_at", "")
                local urlRilis = r.optString("html_url", "https://github.com/" .. fullName .. "/releases")

                local pesan = "Proyek: " .. fullName
                if tag ~= "" then pesan = pesan .. "\nVersi rilis: " .. tag end
                pesan = pesan .. "\nNama berkas: " .. nama .. "\nUkuran: " .. formatUkuranBerkas(ukuran)
                if tglRilis ~= "" then pesan = pesan .. "\nDirilis: " .. tglRilis end
                pesan = pesan .. "\n\nTekan Unduh APK untuk menyimpan berkas langsung ke folder Download HP Anda."
                if service.speak then service.speak("APK siap diunduh. " .. nama) end

                PembuatAPK.dialogTombol("APK Siap Diunduh", pesan, {
                    {"unduh APK", function()
                        unduhLangsungKeFolderDownload(urlApi, nama, token, false, kembali, true, tautan)
                    end},
                    {"salin tautan unduhan", function() salinKeClipboard("Tautan APK", tautan) end, tetap = true},
                    {"cek status pembangunan", function() PembuatAPK.cekStatus(fullName, token, kembali) end},
                    {"buka halaman rilis di web", function() bukaBrowser(urlRilis) end},
                }, {"kembali", kembali})
                return
            end
        end

        local endpointArt = "https://api.github.com/repos/" .. fullName .. "/actions/artifacts?per_page=20"
        kirimPermintaanGitHub("GET", endpointArt, token, nil, function(okArt, resArt)
            if okArt then
                local objArt = JSONObject(resArt)
                local arrArt = objArt.optJSONArray("artifacts")
                if arrArt ~= nil and arrArt.length() > 0 then
                    local daftarNama = {}
                    local daftarData = {}

                    for i = 0, arrArt.length() - 1 do
                        local item = arrArt.getJSONObject(i)
                        local artName = item.optString("name", "")
                        local artSize = item.optLong("size_in_bytes", 0)
                        table.insert(daftarNama, (i + 1) .. ". " .. artName .. " (" .. formatUkuranBerkas(artSize) .. ")")
                        table.insert(daftarData, item)
                    end

                    local bPilihArt = AlertDialog.Builder(service)
                    bPilihArt.setTitle("Pilih Berkas Artefak (" .. #daftarData .. ")")
                    bPilihArt.setItems(daftarNama, DialogInterface.OnClickListener{
                        onClick = function(dArt, whichArt)
                            local terpilih = daftarData[whichArt + 1]
                            local artNama = terpilih.optString("name", "aplikasi-apk")
                            local artUrl = terpilih.optString("archive_download_url", "")

                            PembuatAPK.dialogTombol("Unduh & Ekstrak APK",
                                "Berkas: " .. artNama .. "\n\nTekan Unduh APK untuk mengunduh dan otomatis mengekstrak berkas .apk ke folder Download HP Anda.",
                                {
                                    {"unduh APK", function()
                                        unduhLangsungKeFolderDownload(artUrl, artNama, token, true, function() PembuatAPK.ambilAPK(fullName, token, kembali) end)
                                    end},
                                    {"salin tautan", function() salinKeClipboard("Tautan Artefak", artUrl) end, tetap = true},
                                }, {"kembali", function() PembuatAPK.ambilAPK(fullName, token, kembali) end})
                        end
                    })
                    bPilihArt.setNegativeButton("kembali", DialogInterface.OnClickListener{
                        onClick = function() kembali() end
                    })
                    local dPArt = bPilihArt.create()
                    dPArt.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                    dPArt.show()
                    aturTombolHurufKecil(dPArt, nil, "kembali", nil)
                    if service.speak then service.speak("Ditemukan " .. #daftarData .. " berkas artefak. Silakan pilih.") end
                    return
                end
            end

            local tombolBelum = {
                {"cek status pembangunan", function() PembuatAPK.cekStatus(fullName, token, kembali) end},
                {"buka actions di web", function() bukaBrowser("https://github.com/" .. fullName .. "/actions") end},
            }
            if not okArt then
                PembuatAPK.tampilError("Gagal mengambil APK",
                    "Proyek: " .. fullName .. "\n\nRilis: " .. tostring(resRel) .. "\nArtefak: " .. tostring(resArt),
                    kembali, tombolBelum)
            else
                PembuatAPK.dialogTombol("APK Belum Siap",
                    "Belum ada APK di rilis maupun artefak repo ini. Pembangunan mungkin belum selesai atau belum pernah dijalankan. Silakan cek status pembangunan.",
                    tombolBelum, {"kembali", kembali})
            end
        end)
    end)
end

-- ===== Tanda tangan pribadi (v1.18): buat, impor, ekspor, kelola, dan pakai saat membangun APK =====
TandaTangan = {}

local KEY_TANDA_TANGAN = "key_daftar_tanda_tangan_pribadi_unik"
local KS_JALUR = ".tanda-tangan/kunci.p12"
local PROP_JALUR = ".tanda-tangan/sandi.properties"
local PENANDA_TT = "# tanda-tangan-pribadi: v2"
local SKIP_CI = " [skip ci]"

-- ---------- bantu: byte <-> string ----------

local function bytesKeString(arr)
    local t = {}
    for i = 0, #arr - 1 do t[#t + 1] = string.char((arr[i] + 256) % 256) end
    return table.concat(t)
end

local function stringKeBytes(s)
    local bos = ByteArrayOutputStream()
    for i = 1, #s do bos.write(s:byte(i)) end
    return bos.toByteArray()
end

local function bacaBerkasKeBytes(fileObj)
    local fis = FileInputStream(fileObj)
    local bos = ByteArrayOutputStream()
    local buf = String(string.rep(" ", 4096)).getBytes()
    local n = fis.read(buf)
    while n ~= -1 do
        bos.write(buf, 0, n)
        n = fis.read(buf)
    end
    fis.close()
    return bos.toByteArray()
end

local function tulisBytesKeBerkas(fileObj, data)
    local fos = FileOutputStream(fileObj)
    fos.write(data)
    fos.flush()
    fos.close()
end

local function sidikJari(derBytes)
    local d = MessageDigest.getInstance("SHA-256").digest(derBytes)
    local bagian = {}
    for i = 0, #d - 1 do
        bagian[#bagian + 1] = string.format("%02X", (d[i] + 256) % 256)
    end
    return table.concat(bagian, ":")
end

local function sandiAcak()
    local huruf = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    local sr = SecureRandom()
    local out = {}
    for i = 1, 16 do
        local k = sr.nextInt(#huruf) + 1
        out[i] = huruf:sub(k, k)
    end
    return table.concat(out)
end

-- ---------- bantu: DER (sertifikat X.509 self-signed) ----------

local function derPanjang(n)
    if n < 128 then
        return string.char(n)
    elseif n < 256 then
        return string.char(0x81, n)
    elseif n < 65536 then
        return string.char(0x82, math.floor(n / 256), n % 256)
    end
    return string.char(0x83, math.floor(n / 65536), math.floor(n / 256) % 256, n % 256)
end

local function tlv(tag, ...)
    local isi = table.concat({...})
    return string.char(tag) .. derPanjang(#isi) .. isi
end

local function seq(...) return tlv(0x30, ...) end
local function himpunan(...) return tlv(0x31, ...) end

local function oid(...)
    local a = {...}
    local out = {string.char(a[1] * 40 + a[2])}
    for i = 3, #a do
        local v = a[i]
        local bagian = {v % 128}
        v = math.floor(v / 128)
        while v > 0 do
            table.insert(bagian, 1, 128 + v % 128)
            v = math.floor(v / 128)
        end
        out[#out + 1] = string.char((table.unpack or unpack)(bagian))
    end
    return tlv(0x06, table.concat(out))
end

local function derWaktu(t)
    local y, mo, d, h, mi, s = t.year, t.month, t.day, t.hour, t.min, t.sec
    if y >= 2050 then
        return tlv(0x18, string.format("%04d%02d%02d%02d%02d%02dZ", y, mo, d, h, mi, s))
    end
    return tlv(0x17, string.format("%02d%02d%02d%02d%02d%02dZ", y % 100, mo, d, h, mi, s))
end

local function atributNama(oidAtribut, tagTeks, nilai)
    return himpunan(seq(oidAtribut, tlv(tagTeks, nilai)))
end

local function namaX500(cn, o, c)
    local bagian = {}
    if c and c ~= "" then table.insert(bagian, atributNama(oid(2, 5, 4, 6), 0x13, c)) end
    if o and o ~= "" then table.insert(bagian, atributNama(oid(2, 5, 4, 10), 0x0C, o)) end
    table.insert(bagian, atributNama(oid(2, 5, 4, 3), 0x0C, cn))
    return tlv(0x30, table.concat(bagian))
end

local function buatSertifikatDer(kp, cn, o, c, tahun)
    local algo = seq(oid(1, 2, 840, 113549, 1, 1, 11), tlv(0x05, ""))

    local sb = String(string.rep(" ", 16)).getBytes()
    SecureRandom().nextBytes(sb)
    local sn = bytesKeString(sb)
    local b1 = sn:byte(1) % 128
    if b1 == 0 then b1 = 1 end
    sn = string.char(b1) .. sn:sub(2)
    local serial = tlv(0x02, sn)

    local mulaiT = os.date("!*t", os.time() - 86400)
    local akhirT = {year = mulaiT.year + tahun, month = mulaiT.month, day = mulaiT.day,
                    hour = mulaiT.hour, min = mulaiT.min, sec = mulaiT.sec}
    if akhirT.month == 2 and akhirT.day == 29 then akhirT.day = 28 end

    local nama = namaX500(cn, o, c)
    local tbs = seq(
        tlv(0xA0, tlv(0x02, "\2")),
        serial, algo, nama,
        seq(derWaktu(mulaiT), derWaktu(akhirT)),
        nama,
        bytesKeString(kp.getPublic().getEncoded()))

    local sg = Signature.getInstance("SHA256withRSA")
    sg.initSign(kp.getPrivate())
    sg.update(stringKeBytes(tbs))
    local sig = bytesKeString(sg.sign())
    return seq(tbs, algo, tlv(0x03, "\0" .. sig))
end

-- buat keystore PKCS12; mengembalikan {data (byte[] Java), alias, sandi, sidik}
function TandaTangan.buatKeystore(nama, organisasi, negara, alias, sandi, tahun)
    local g = KeyPairGenerator.getInstance("RSA")
    g.initialize(2048, SecureRandom())
    local kp = g.generateKeyPair()

    local der = buatSertifikatDer(kp, nama, organisasi, negara, tahun)
    local derBytes = stringKeBytes(der)
    local cert = CertificateFactory.getInstance("X.509").generateCertificate(ByteArrayInputStream(derBytes))

    local ks = KeyStore.getInstance("PKCS12")
    ks.load(nil, nil)
    local pw = String(sandi).toCharArray()
    local rantai
    local okArr = pcall(function()
        local JA = luajava.bindClass("java.lang.reflect.Array")
        rantai = JA.newInstance(cert.getClass(), 1)
        JA.set(rantai, 0, cert)
    end)
    if not okArr then rantai = {cert} end
    ks.setKeyEntry(alias, kp.getPrivate(), pw, rantai)
    local bos = ByteArrayOutputStream()
    ks.store(bos, pw)

    return {data = bos.toByteArray(), alias = alias, sandi = sandi, sidik = sidikJari(derBytes)}
end

-- ---------- daftar tanda tangan (disimpan di pengaturan aplikasi) ----------

function TandaTangan.ambilDaftar()
    local hasil = {}
    pcall(function()
        local arr = JSONArray(prefs.getString(KEY_TANDA_TANGAN, "[]"))
        for i = 0, arr.length() - 1 do
            local o = arr.getJSONObject(i)
            table.insert(hasil, {
                id = tostring(o.optString("id", "")),
                nama = tostring(o.optString("nama", "")),
                alias = tostring(o.optString("alias", "")),
                sandi = tostring(o.optString("sandi", "")),
                sidik = tostring(o.optString("sidik", "")),
                slug = tostring(o.optString("slug", "")),
                unduhan = tostring(o.optString("unduhan", "")),
                diekspor = o.optBoolean("diekspor", false),
                dibuat = tonumber(o.optString("dibuat", "0")) or 0
            })
        end
    end)
    return hasil
end

function TandaTangan.simpanDaftar(daftar)
    local arr = JSONArray()
    for _, o in ipairs(daftar) do
        local j = JSONObject()
        j.put("id", o.id)
        j.put("nama", o.nama)
        j.put("alias", o.alias)
        j.put("sandi", o.sandi)
        j.put("sidik", o.sidik)
        j.put("slug", o.slug)
        j.put("unduhan", o.unduhan)
        j.put("diekspor", o.diekspor and true or false)
        j.put("dibuat", string.format("%d", o.dibuat or 0))
        arr.put(j)
    end
    prefs.edit().putString(KEY_TANDA_TANGAN, arr.toString()).apply()
end

function TandaTangan.tambah(rec)
    local d = TandaTangan.ambilDaftar()
    table.insert(d, rec)
    TandaTangan.simpanDaftar(d)
end

function TandaTangan.hapusDariDaftar(id)
    local baru = {}
    for _, o in ipairs(TandaTangan.ambilDaftar()) do
        if o.id ~= id then table.insert(baru, o) end
    end
    TandaTangan.simpanDaftar(baru)
end

function TandaTangan.tandaiDiekspor(id)
    local d = TandaTangan.ambilDaftar()
    for _, o in ipairs(d) do
        if o.id == id then o.diekspor = true end
    end
    TandaTangan.simpanDaftar(d)
end

function TandaTangan.berkasKunci(id)
    local d = File(service.getFilesDir(), "tanda_tangan")
    if not d.exists() then d.mkdirs() end
    return File(d, id .. ".p12")
end

function TandaTangan.label(o)
    local t = o.nama .. " (alias " .. o.alias
    if o.dibuat and o.dibuat > 0 then
        t = t .. ", dibuat " .. os.date("%d %b %Y %H:%M", o.dibuat)
    end
    return t .. ")"
end

local function buatIdBaru()
    return string.format("%d", os.time()) .. string.format("%03d", math.random(0, 999))
end

local function buatSlugTT(nama)
    local s = buatSlug(nama)
    if s == "" then s = "tanda-tangan" end
    return s .. "-" .. os.date("%Y%m%d-%H%M")
end

-- ---------- ekspor ke folder Download ----------

local function teksInfo(nama, alias, sandi, sidik, slug)
    return "TANDA TANGAN APK - SIMPAN BAIK-BAIK\n\nNama pemilik: " .. nama
        .. "\nAlias: " .. alias .. "\nSandi: " .. sandi
        .. "\nSidik jari SHA-256: " .. sidik
        .. "\nBerkas: " .. slug .. ".p12 (format PKCS12)"
        .. "\n\nSandi tertulis di berkas ini. Jangan membagikannya ke orang lain.\n"
end

-- simpan .p12 dan -info.txt ke folder Download; mengembalikan lokasi .p12
function TandaTangan.eksporSatu(o)
    local f = TandaTangan.berkasKunci(o.id)
    if not f.exists() then error("Salinan di dalam aplikasi tidak ditemukan") end
    local slug = o.slug ~= "" and o.slug or "tanda-tangan"
    local lok = Pengunduh.simpanBytes(slug .. ".p12", "application/x-pkcs12", bacaBerkasKeBytes(f))
    Pengunduh.simpanBytes(slug .. "-info.txt", "text/plain",
        String(teksInfo(o.nama, o.alias, o.sandi, o.sidik, slug)).getBytes("UTF-8"))
    return lok
end

function TandaTangan.eksporSemua(token, kembali, setelah)
    local ok, gagal = 0, {}
    local total = 0
    for _, o in ipairs(TandaTangan.ambilDaftar()) do
        if not o.diekspor then
            total = total + 1
            local sukses, err = pcall(function() TandaTangan.eksporSatu(o) end)
            if sukses then
                TandaTangan.tandaiDiekspor(o.id)
                ok = ok + 1
            else
                table.insert(gagal, "- " .. o.nama .. ": " .. tostring(err))
            end
        end
    end
    local pesan = ok .. " dari " .. total .. " tanda tangan tersimpan di folder Download (berkas .p12 dan -info.txt)."
    if #gagal > 0 then pesan = pesan .. "\nGagal:\n" .. table.concat(gagal, "\n") end
    if service.speak then service.speak(pesan) end
    tampilDialog("Simpan ke Download", pesan, {"oke", function() TandaTangan.kelola(token, kembali, setelah) end})
end

-- ---------- dialog bantu: formulir isian ----------

local function dialogForm(judul, pesan, daftarField, teksOk, onOk, onBatal)
    local layout = LinearLayout(service)
    layout.setOrientation(LinearLayout.VERTICAL)
    layout.setPadding(40, 20, 40, 10)

    local inputs = {}
    for i, f in ipairs(daftarField) do
        local tv = TextView(service)
        tv.setText(f.label)
        layout.addView(tv)
        local et = EditText(service)
        et.setHint(f.hint or "")
        et.setSingleLine(true)
        if f.nilai and f.nilai ~= "" then et.setText(f.nilai) end
        layout.addView(et)
        inputs[i] = et
    end

    local scroll = ScrollView(service.getApplicationContext())
    scroll.setFillViewport(true)
    scroll.addView(layout)

    local b = AlertDialog.Builder(service)
    b.setTitle(judul)
    if pesan and pesan ~= "" then b.setMessage(pesan) end
    b.setView(scroll)
    b.setPositiveButton(teksOk, DialogInterface.OnClickListener{
        onClick = function()
            local nilai = {}
            for i, et in ipairs(inputs) do
                nilai[i] = tostring(et.getText()):match("^%s*(.-)%s*$")
            end
            onOk(nilai)
        end
    })
    b.setNegativeButton("kembali", DialogInterface.OnClickListener{
        onClick = function() if onBatal then onBatal() end end
    })
    local diag = b.create()
    diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    diag.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
    diag.show()
    aturTombolHurufKecil(diag, teksOk, "kembali", nil)
end

-- ---------- daftar dan rincian ----------

function TandaTangan.kelola(token, kembali, setelah)
    local daftar = TandaTangan.ambilDaftar()
    local tombol = {
        {"Buat tanda tangan baru", function() TandaTangan.formBuat({}, token, kembali, setelah) end},
        {"Impor tanda tangan dari folder Download", function() TandaTangan.mulaiImpor(token, kembali, setelah) end},
    }
    local adaBelum = false
    for _, o in ipairs(daftar) do
        table.insert(tombol, {TandaTangan.label(o), function() TandaTangan.rincian(o, token, kembali, setelah) end})
        if not o.diekspor then adaBelum = true end
    end
    if adaBelum then
        table.insert(tombol, {"Simpan semua yang belum diekspor ke folder Download",
            function() TandaTangan.eksporSemua(token, kembali, setelah) end})
    end
    local pesan = "Tanda tangan dipakai untuk menandatangani APK versi rilis. Simpan berkasnya baik-baik: "
        .. "aplikasi yang dipasang dengan satu tanda tangan hanya bisa diperbarui dengan tanda tangan yang sama."
    if #daftar == 0 then pesan = pesan .. "\n\nBelum ada tanda tangan pribadi." end
    if service.speak then service.speak("Tanda tangan pribadi. " .. #daftar .. " tanda tangan tersimpan.") end
    PembuatAPK.dialogTombol("Tanda tangan pribadi", pesan, tombol, {"kembali", kembali})
end

function TandaTangan.rincian(o, token, kembali, setelah)
    local pesan = "Nama: " .. o.nama
        .. "\nAlias: " .. o.alias
        .. "\nSandi: " .. o.sandi
        .. "\nSidik jari SHA-256:\n" .. o.sidik
        .. "\n\nBerkas: " .. o.unduhan
    if o.diekspor then
        pesan = pesan .. "\n\nSudah tersimpan di folder Download (berkas .p12 dan -info.txt). Tidak perlu disimpan lagi."
    end
    local tombol = {
        {"salin sandi", function() salinKeClipboard("Sandi tanda tangan", o.sandi) end, tetap = true},
    }
    if not o.diekspor then
        table.insert(tombol, {"simpan ke folder Download (p12 dan info)", function()
            local ok, hasil = pcall(function() return TandaTangan.eksporSatu(o) end)
            local pesanHasil
            if ok then
                TandaTangan.tandaiDiekspor(o.id)
                pesanHasil = "Tersimpan: " .. tostring(hasil) .. "\nBerkas -info.txt berisi alias dan sandi ikut disimpan di folder yang sama."
            else
                pesanHasil = "Gagal menyimpan: " .. tostring(hasil)
            end
            if service.speak then service.speak(pesanHasil) end
            tampilDialog("Simpan ke Download", pesanHasil, {"oke", function() TandaTangan.kelola(token, kembali, setelah) end})
        end})
    end
    table.insert(tombol, {"hapus dari aplikasi", function()
        tampilDialog("Hapus tanda tangan?",
            "Salinan di dalam aplikasi dihapus. Berkas di folder Download tidak ikut terhapus. Tanpa berkas itu, aplikasi yang sudah dipasang dengan tanda tangan ini tidak bisa diperbarui.",
            {"hapus", function()
                TandaTangan.hapusDariDaftar(o.id)
                pcall(function()
                    local f = TandaTangan.berkasKunci(o.id)
                    if f.exists() then f.delete() end
                end)
                TandaTangan.kelola(token, kembali, setelah)
            end}, nil,
            {"batal", function() TandaTangan.rincian(o, token, kembali, setelah) end})
    end})
    PembuatAPK.dialogTombol("Tanda tangan pribadi", pesan, tombol,
        {"kembali", function() TandaTangan.kelola(token, kembali, setelah) end})
end

-- ---------- buat ----------

function TandaTangan.formBuat(awal, token, kembali, setelah)
    awal = awal or {}
    local fields = {
        {label = "Nama pemilik (wajib)", hint = "contoh: Novan", nilai = awal[1] or ""},
        {label = "Organisasi (boleh kosong)", hint = "contoh: Novan Studio", nilai = awal[2] or ""},
        {label = "Kode negara, 2 huruf", hint = "contoh: ID", nilai = awal[3] or "ID"},
        {label = "Alias kunci", hint = "tanpa spasi", nilai = awal[4] or "kunci"},
        {label = "Sandi (kosongkan agar dibuat otomatis)", hint = "minimal 6 karakter", nilai = awal[5] or ""},
    }
    dialogForm("Buat tanda tangan baru",
        "Kunci RSA 2048 bit, berlaku 27 tahun. Hasilnya disimpan di folder Download pada penyimpanan internal.",
        fields, "buat dan simpan", function(n)
            local nama, org, negara, alias, sandi = n[1], n[2], n[3]:upper(), n[4], n[5]
            local ulang = {nama, org, negara, alias, sandi}
            local function tolak(pesan)
                Toast.makeText(service, pesan, Toast.LENGTH_LONG).show()
                if service.speak then service.speak(pesan) end
                TandaTangan.formBuat(ulang, token, kembali, setelah)
            end
            if nama == "" then return tolak("Nama pemilik wajib diisi.") end
            if negara ~= "" and not negara:match("^%u%u$") then return tolak("Kode negara harus 2 huruf, misalnya ID.") end
            if alias == "" or not alias:match("^[%w_%-]+$") then
                return tolak("Alias hanya boleh huruf, angka, garis bawah, atau tanda hubung, tanpa spasi.")
            end
            if sandi == "" then sandi = sandiAcak() end
            if #sandi < 6 then return tolak("Sandi minimal 6 karakter.") end
            if sandi:find(" ", 1, true) then return tolak("Sandi tidak boleh memakai spasi.") end
            TandaTangan.proses(nama, org, negara, alias, sandi, token, kembali, setelah)
        end, function() TandaTangan.kelola(token, kembali, setelah) end)
end

function TandaTangan.proses(nama, org, negara, alias, sandi, token, kembali, setelah)
    local progress = ProgressDialog(service)
    progress.setTitle("Membuat tanda tangan")
    progress.setMessage("Membuat kunci, mohon tunggu beberapa detik...")
    progress.setCancelable(false)
    progress.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    progress.show()

    Thread(Runnable{
        run = function()
            local ok, h = pcall(function()
                return TandaTangan.buatKeystore(nama, org, negara, alias, sandi, 27)
            end)
            mainHandler.post(Runnable{
                run = function()
                    pcall(function() progress.dismiss() end)
                    if not ok then
                        PembuatAPK.tampilError("Gagal membuat tanda tangan", tostring(h),
                            function() TandaTangan.kelola(token, kembali, setelah) end)
                        return
                    end
                    local okSimpan, errSimpan = pcall(function()
                        local id = buatIdBaru()
                        tulisBytesKeBerkas(TandaTangan.berkasKunci(id), h.data)
                        local slug = buatSlugTT(nama)
                        local rec = {id = id, nama = nama, alias = h.alias, sandi = h.sandi, sidik = h.sidik,
                                     slug = slug, unduhan = "belum diekspor", diekspor = false, dibuat = os.time()}
                        -- simpan juga ke folder Download (p12 dan info)
                        local okEks, lok = pcall(function()
                            local l = Pengunduh.simpanBytes(slug .. ".p12", "application/x-pkcs12", h.data)
                            local info = "TANDA TANGAN APK - SIMPAN BAIK-BAIK\n\nNama pemilik: " .. nama
                                .. "\nOrganisasi: " .. org .. "\nNegara: " .. negara
                                .. "\nAlias: " .. h.alias .. "\nSandi: " .. h.sandi
                                .. "\nSidik jari SHA-256: " .. h.sidik
                                .. "\nBerkas: " .. slug .. ".p12 (format PKCS12)"
                                .. "\n\nSandi tertulis di berkas ini. Jangan membagikannya ke orang lain.\n"
                            Pengunduh.simpanBytes(slug .. "-info.txt", "text/plain", String(info).getBytes("UTF-8"))
                            return l
                        end)
                        if okEks then
                            rec.unduhan = tostring(lok)
                            rec.diekspor = true
                        end
                        TandaTangan.tambah(rec)
                        if service.speak then service.speak("Tanda tangan dibuat.") end
                        if not okEks then
                            Toast.makeText(service, "Tanda tangan dibuat, tetapi gagal disimpan ke Download: " .. tostring(lok), Toast.LENGTH_LONG).show()
                        end
                        if setelah then setelah() else TandaTangan.rincian(rec, token, kembali, setelah) end
                    end)
                    if not okSimpan then
                        PembuatAPK.tampilError("Gagal menyimpan tanda tangan", tostring(errSimpan),
                            function() TandaTangan.kelola(token, kembali, setelah) end)
                    end
                end
            })
        end
    }).start()
end

-- ---------- impor ----------

local function bacaInfoTeks(teks)
    local r = {}
    for baris in (teks .. "\n"):gmatch("(.-)\r?\n") do
        local k, v = baris:match("^%s*([^:=]-)%s*[:=]%s*(.-)%s*$")
        if k and v and v ~= "" then
            local kk = k:lower()
            if kk == "sandi" and not r.sandi then r.sandi = v
            elseif kk == "alias" and not r.alias then r.alias = v
            elseif kk == "nama pemilik" and not r.nama then r.nama = v end
        end
    end
    return r
end

function TandaTangan.mulaiImpor(token, kembali, setelah)
    PembuatAPK.dialogTombol("Impor tanda tangan",
        "Pilih berkas keystore berakhiran .p12 dari folder Download atau penyimpanan lain.\n\n"
        .. "Bila ada berkas -info.txt dengan nama yang sama di folder itu (hasil ekspor aplikasi ini), alias dan sandi akan terisi otomatis. Bila tidak ada, sandi akan ditanyakan.",
        {{"pilih berkas", function()
            local dl = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            TandaTangan.jelajah(tostring(dl.getAbsolutePath()), token, kembali, setelah)
        end}},
        {"batal", function() TandaTangan.kelola(token, kembali, setelah) end})
end

function TandaTangan.jelajah(pathSekarang, token, kembali, setelah)
    local akar = tostring(Environment.getExternalStorageDirectory().getAbsolutePath())
    local dir = File(pathSekarang)
    local files = dir.listFiles()
    local menuItems, dataItems = {}, {}

    if pathSekarang ~= akar and pathSekarang ~= "/" and dir.getParent() then
        table.insert(menuItems, "Folder .. (naik satu tingkat)")
        table.insert(dataItems, {tipe = "naik", path = tostring(dir.getParent())})
    end

    if files ~= nil then
        local daftarFolder, daftarBerkas = {}, {}
        for i = 0, #files - 1 do
            local f = files[i]
            local nama = tostring(f.getName())
            if not nama:find("^%.") then
                if f.isDirectory() then
                    table.insert(daftarFolder, f)
                else
                    local n = nama:lower()
                    if n:find("%.p12$") or n:find("%.pfx$") then table.insert(daftarBerkas, f) end
                end
            end
        end
        table.sort(daftarFolder, function(a, b) return tostring(a.getName()):lower() < tostring(b.getName()):lower() end)
        table.sort(daftarBerkas, function(a, b) return tostring(a.getName()):lower() < tostring(b.getName()):lower() end)
        for _, f in ipairs(daftarFolder) do
            table.insert(menuItems, "Folder " .. tostring(f.getName()))
            table.insert(dataItems, {tipe = "dir", file = f})
        end
        for _, f in ipairs(daftarBerkas) do
            table.insert(menuItems, "Berkas " .. tostring(f.getName()) .. " (" .. formatUkuranBerkas(f.length()) .. ")")
            table.insert(dataItems, {tipe = "file", file = f})
        end
    end

    local b = AlertDialog.Builder(service)
    b.setTitle("Pilih berkas .p12: " .. tostring(dir.getName()))
    if files == nil then
        b.setMessage("Folder ini tidak bisa dibaca. Pastikan aplikasi punya izin mengakses penyimpanan.")
    elseif #menuItems == 0 then
        b.setMessage("Tidak ada berkas .p12 atau folder di sini.")
    else
        b.setItems(menuItems, DialogInterface.OnClickListener{
            onClick = function(_, which)
                local item = dataItems[which + 1]
                if item.tipe == "naik" then
                    TandaTangan.jelajah(item.path, token, kembali, setelah)
                elseif item.tipe == "dir" then
                    TandaTangan.jelajah(tostring(item.file.getAbsolutePath()), token, kembali, setelah)
                else
                    TandaTangan.sesudahPilih(item.file, token, kembali, setelah)
                end
            end
        })
    end
    b.setNegativeButton("kembali", DialogInterface.OnClickListener{
        onClick = function() TandaTangan.kelola(token, kembali, setelah) end
    })
    local diag = b.create()
    diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    diag.show()
    aturTombolHurufKecil(diag, nil, "kembali", nil)
end

function TandaTangan.sesudahPilih(berkas, token, kembali, setelah)
    local ok, data = pcall(function() return bacaBerkasKeBytes(berkas) end)
    if not ok or data == nil or #data == 0 or (data[0] + 256) % 256 ~= 0x30 then
        Toast.makeText(service, "Berkas ini bukan keystore PKCS12 yang valid.", Toast.LENGTH_LONG).show()
        TandaTangan.jelajah(tostring(berkas.getParent()), token, kembali, setelah)
        return
    end
    local nama = tostring(berkas.getName())
    local st = {
        data = data, berkas = nama, sandi = "", alias = "", nama = "",
        dariDownload = tostring(berkas.getAbsolutePath()):lower():find("download", 1, true) ~= nil
    }
    pcall(function()
        local dasar = nama:gsub("%.[^.]+$", "")
        local info = File(berkas.getParentFile(), dasar .. "-info.txt")
        if info.exists() then
            local teks = tostring(String(bacaBerkasKeBytes(info), "UTF-8"))
            local r = bacaInfoTeks(teks)
            st.sandi = r.sandi or ""
            st.alias = r.alias or ""
            st.nama = r.nama or ""
        end
    end)
    if st.sandi ~= "" then
        TandaTangan.verifikasi(st, token, kembali, setelah)
    else
        TandaTangan.formImpor(st, "Sandi belum ditemukan. Masukkan sandi keystore.", token, kembali, setelah)
    end
end

function TandaTangan.formImpor(st, pesan, token, kembali, setelah)
    dialogForm("Impor tanda tangan",
        "Berkas keystore: " .. st.berkas .. ((pesan and pesan ~= "") and ("\n\n" .. pesan) or ""),
        {
            {label = "Sandi keystore (wajib)", hint = "sandi tanda tangan", nilai = st.sandi},
            {label = "Alias kunci (boleh kosong, dicari otomatis)", hint = "contoh: kunci", nilai = st.alias},
            {label = "Nama tampilan (boleh kosong)", hint = "contoh: Novan", nilai = st.nama},
        }, "impor", function(n)
            st.sandi, st.alias, st.nama = n[1], n[2], n[3]
            if st.sandi == "" then
                TandaTangan.formImpor(st, "Sandi wajib diisi.", token, kembali, setelah)
                return
            end
            TandaTangan.verifikasi(st, token, kembali, setelah)
        end, function() TandaTangan.kelola(token, kembali, setelah) end)
end

function TandaTangan.verifikasi(st, token, kembali, setelah)
    local ok, hasil = pcall(function()
        local pw = String(st.sandi).toCharArray()
        local ks = KeyStore.getInstance("PKCS12")
        ks.load(ByteArrayInputStream(st.data), pw)
        local al = nil
        if st.alias ~= "" then
            if ks.isKeyEntry(st.alias) then
                al = st.alias
            else
                local en = ks.aliases()
                while en.hasMoreElements() do
                    local x = tostring(en.nextElement())
                    if x:lower() == st.alias:lower() and ks.isKeyEntry(x) then al = x break end
                end
            end
        end
        if al == nil then
            local en = ks.aliases()
            while en.hasMoreElements() do
                local x = tostring(en.nextElement())
                if ks.isKeyEntry(x) then al = x break end
            end
        end
        if al == nil then error("Tidak ada kunci di dalam keystore ini.") end
        if ks.getKey(al, pw) == nil then error("Kunci tidak bisa dibuka dengan sandi ini.") end
        local cert = ks.getCertificate(al)
        if cert == nil then error("Sertifikat tidak ditemukan di dalam keystore.") end
        local sidik = sidikJari(cert.getEncoded())
        local nama = st.nama
        if nama == "" then
            local cn = tostring(cert.getSubjectX500Principal().getName()):match("CN=([^,]+)")
            if cn then nama = cn:match("^%s*(.-)%s*$") end
        end
        if nama == "" then nama = "Tanda tangan impor" end
        return {alias = al, sidik = sidik, nama = nama}
    end)

    if not ok then
        TandaTangan.formImpor(st,
            "Gagal membuka keystore. Pastikan sandi benar dan berkas berformat .p12 (PKCS12).\nRincian: " .. tostring(hasil),
            token, kembali, setelah)
        return
    end

    for _, o in ipairs(TandaTangan.ambilDaftar()) do
        if o.sidik == hasil.sidik then
            local pesanAda = "Tanda tangan ini sudah ada di aplikasi dengan nama " .. o.nama .. "."
            if service.speak then service.speak(pesanAda) end
            tampilDialog("Impor tanda tangan", pesanAda, {"oke", function() TandaTangan.kelola(token, kembali, setelah) end})
            return
        end
    end

    local okSimpan, errSimpan = pcall(function()
        local id = buatIdBaru()
        tulisBytesKeBerkas(TandaTangan.berkasKunci(id), st.data)
        local rec = {id = id, nama = hasil.nama, alias = hasil.alias, sandi = st.sandi, sidik = hasil.sidik,
                     slug = buatSlugTT(hasil.nama), unduhan = "diimpor dari " .. st.berkas,
                     diekspor = st.dariDownload and true or false, dibuat = os.time()}
        TandaTangan.tambah(rec)
        if service.speak then service.speak("Impor berhasil. " .. hasil.nama) end
        Toast.makeText(service, "Impor berhasil: " .. hasil.nama, Toast.LENGTH_SHORT).show()
        if setelah then setelah() else TandaTangan.rincian(rec, token, kembali, setelah) end
    end)
    if not okSimpan then
        PembuatAPK.tampilError("Gagal menyimpan tanda tangan", tostring(errSimpan),
            function() TandaTangan.kelola(token, kembali, setelah) end)
    end
end

-- ---------- berkas di repositori ----------

local function pesanGalatRepo(judul, fullName, res, kembali)
    PembuatAPK.tampilError(judul, "Proyek: " .. fullName .. "\n\n" .. tostring(res), kembali)
end

local function tidakAda(res)
    local r = tostring(res)
    return r:find("404", 1, true) ~= nil or r:find("Not Found", 1, true) ~= nil
end

function TandaTangan.tulisBerkas(fullName, token, jalur, data, pesan, kembali, lanjut)
    local endpoint = "https://api.github.com/repos/" .. fullName .. "/contents/" .. enkodeJalur(jalur)
    kirimPermintaanGitHub("GET", endpoint, token, nil, function(ada, res)
        if not ada and not tidakAda(res) then
            pesanGalatRepo("Gagal memeriksa " .. jalur, fullName, res, kembali)
            return
        end
        local payload = JSONObject()
        payload.put("message", pesan)
        payload.put("content", Base64.encodeToString(data, Base64.NO_WRAP))
        if ada then
            local sha = ""
            pcall(function() sha = tostring(JSONObject(res).optString("sha", "")) end)
            if sha ~= "" then payload.put("sha", sha) end
        end
        kirimPermintaanGitHub("PUT", endpoint, token, payload.toString(), function(ok2, res2)
            if ok2 then
                if lanjut then lanjut() end
            else
                pesanGalatRepo("Gagal mengirim " .. jalur, fullName, res2, kembali)
            end
        end)
    end, true)
end

function TandaTangan.hapusBerkas(fullName, token, jalur, kembali, lanjut)
    local endpoint = "https://api.github.com/repos/" .. fullName .. "/contents/" .. enkodeJalur(jalur)
    kirimPermintaanGitHub("GET", endpoint, token, nil, function(ada, res)
        if not ada then
            if tidakAda(res) then
                if lanjut then lanjut() end
            else
                pesanGalatRepo("Gagal memeriksa " .. jalur, fullName, res, kembali)
            end
            return
        end
        local sha = ""
        pcall(function() sha = tostring(JSONObject(res).optString("sha", "")) end)
        if sha == "" then
            if lanjut then lanjut() end
            return
        end
        local payload = JSONObject()
        payload.put("message", "Hapus tanda tangan pribadi dari repo" .. SKIP_CI)
        payload.put("sha", sha)
        kirimPermintaanGitHub("DELETE", endpoint, token, payload.toString(), function(ok2, res2)
            if ok2 or tidakAda(res2) then
                if lanjut then lanjut() end
            else
                pesanGalatRepo("Gagal menghapus " .. jalur, fullName, res2, kembali)
            end
        end)
    end, true)
end

-- pastikan alur kerja di repo mengenal tanda tangan pribadi (perbarui bila buatan aplikasi tetapi versi lama)
function TandaTangan.pastikanAlurKerja(fullName, token, kembali, lanjut)
    local jalur = ".github/workflows/" .. NAMA_ALUR_KERJA
    local endpoint = "https://api.github.com/repos/" .. fullName .. "/contents/" .. enkodeJalur(jalur)
    kirimPermintaanGitHub("GET", endpoint, token, nil, function(ada, res)
        if not ada then
            if tidakAda(res) then
                if lanjut then lanjut() end -- belum ada: bangunUlang akan memasang templat terbaru
            else
                pesanGalatRepo("Gagal memeriksa alur kerja", fullName, res, kembali)
            end
            return
        end
        local obj = JSONObject(res)
        local sha = tostring(obj.optString("sha", ""))
        local isi = ""
        pcall(function()
            local b64 = tostring(obj.optString("content", "")):gsub("%s+", "")
            isi = tostring(String(Base64.decode(b64, Base64.DEFAULT), "UTF-8"))
        end)
        if isi:find(PENANDA_TT, 1, true) then
            if lanjut then lanjut() end
            return
        end
        local function ganti()
            local slug = buatSlug(fullName:match("[^/]+$") or "aplikasi")
            if slug == "" then slug = "aplikasi" end
            local baru = isiTemplat(TEMPLAT.workflowLengkap, {NAMA_APK = slug})
            local payload = JSONObject()
            payload.put("message", "Perbarui alur kerja: dukung tanda tangan pribadi" .. SKIP_CI)
            payload.put("content", Base64.encodeToString(String(baru).getBytes("UTF-8"), Base64.NO_WRAP))
            payload.put("sha", sha)
            kirimPermintaanGitHub("PUT", endpoint, token, payload.toString(), function(ok2, res2)
                if ok2 then
                    if lanjut then lanjut() end
                else
                    local info = "Proyek: " .. fullName .. "\n\n" .. tostring(res2)
                    if tostring(res2):lower():find("workflow", 1, true) then
                        info = info .. "\n\nToken GitHub perlu izin workflow. Buat token baru dengan izin repo dan workflow."
                    end
                    PembuatAPK.tampilError("Gagal memperbarui alur kerja", info, kembali)
                end
            end)
        end
        if isi:find("name: Bangun APK Android", 1, true) or isi:find("name: Build Android APK", 1, true) then
            ganti()
            return
        end
        PembuatAPK.dialogTombol("Alur kerja bukan buatan aplikasi",
            "Berkas " .. jalur .. " di repo ini tidak dibuat oleh aplikasi ini sehingga belum bisa memakai tanda tangan pribadi.\n\nGanti dengan alur kerja aplikasi? Isi lamanya akan tertimpa (masih ada di riwayat commit). Syarat: proyek Gradle dengan modul bernama app.",
            {{"ganti alur kerja dan lanjut", ganti}}, {"batal", kembali})
    end, true)
end

-- ---------- pintu masuk: Mulai pembangunan APK ----------

function TandaTangan.mulai(fullName, token, kb)
    local kembali = tetapkanKembali(fullName, token, kb)
    local pesan = "Proyek: " .. fullName
        .. "\n\nTanda tangan bawaan GitHub: APK dibangun versi debug dan ditandatangani kunci sementara milik GitHub. Cocok untuk mencoba; kuncinya berbeda di setiap pembangunan sehingga aplikasi yang sudah terpasang tidak bisa diperbarui lewat APK berikutnya kecuali dicopot dulu."
        .. "\n\nTanda tangan pribadi: APK dibangun versi rilis dan ditandatangani kunci milik Anda sendiri, sehingga selalu bisa diperbarui. Aplikasi mengirim keystore ke repo ini (hanya repo privat)."
    PembuatAPK.dialogTombol("Pilih tanda tangan APK", pesan, {
        {"tanda tangan bawaan GitHub", function() TandaTangan.pakaiBawaan(fullName, token, kembali) end},
        {"tanda tangan pribadi", function() TandaTangan.pakaiPribadi(fullName, token, kembali) end},
    }, {"batal", kembali})
end

function TandaTangan.pakaiBawaan(fullName, token, kembali)
    -- Bila sebelumnya repo pernah diberi tanda tangan pribadi, kunci dihapus agar alur kerja memakai kunci bawaan.
    TandaTangan.hapusBerkas(fullName, token, PROP_JALUR, kembali, function()
        TandaTangan.hapusBerkas(fullName, token, KS_JALUR, kembali, function()
            PembuatAPK.bangunUlang(fullName, token, kembali)
        end)
    end)
end

function TandaTangan.pakaiPribadi(fullName, token, kembali)
    local ulang = function() TandaTangan.mulai(fullName, token, kembali) end
    kirimPermintaanGitHub("GET", "https://api.github.com/repos/" .. fullName, token, nil, function(ok, res)
        if not ok then
            PembuatAPK.tampilError("Gagal membaca proyek", "Proyek: " .. fullName .. "\n\n" .. tostring(res), ulang,
                {{"coba lagi", function() TandaTangan.pakaiPribadi(fullName, token, kembali) end}})
            return
        end
        if not JSONObject(res).optBoolean("private", false) then
            PembuatAPK.dialogTombol("Repo ini publik",
                "Tanda tangan pribadi tidak dikirim ke repo publik, karena keystore dan sandinya akan terlihat oleh semua orang dan siapa pun bisa memalsukan APK atas nama Anda.\n\nJadikan repo ini privat lebih dulu (menu repositori, ubah privasi), atau pakai tanda tangan bawaan GitHub.",
                {{"pakai tanda tangan bawaan GitHub", function() TandaTangan.pakaiBawaan(fullName, token, kembali) end}},
                {"kembali", ulang})
            return
        end
        local daftar = TandaTangan.ambilDaftar()
        local lanjutSetelah = function() TandaTangan.pakaiPribadi(fullName, token, kembali) end
        local kembaliKelola = ulang
        if #daftar == 0 then
            PembuatAPK.dialogTombol("Belum ada tanda tangan pribadi",
                "Buat tanda tangan pribadi lebih dulu, atau impor dari folder Download bila Anda pernah menyimpannya (misalnya setelah aplikasi dipasang ulang). Setelah itu pembangunan APK dilanjutkan.",
                {
                    {"buat tanda tangan pribadi", function() TandaTangan.formBuat({}, token, kembaliKelola, lanjutSetelah) end},
                    {"impor tanda tangan dari folder Download", function() TandaTangan.mulaiImpor(token, kembaliKelola, lanjutSetelah) end},
                    {"pakai tanda tangan bawaan GitHub", function() TandaTangan.pakaiBawaan(fullName, token, kembali) end},
                }, {"kembali", ulang})
            return
        end
        TandaTangan.pilih(fullName, token, daftar, kembali)
    end)
end

function TandaTangan.pilih(fullName, token, daftar, kembali)
    local ulang = function() TandaTangan.mulai(fullName, token, kembali) end
    local lanjutSetelah = function() TandaTangan.pakaiPribadi(fullName, token, kembali) end
    local tombol = {}
    for i, o in ipairs(daftar) do
        table.insert(tombol, {i .. ". " .. TandaTangan.label(o), function()
            TandaTangan.konfirmasi(fullName, token, o, kembali)
        end})
    end
    table.insert(tombol, {"tambah: buat tanda tangan baru", function()
        TandaTangan.formBuat({}, token, ulang, lanjutSetelah)
    end})
    table.insert(tombol, {"tambah: impor dari folder Download", function()
        TandaTangan.mulaiImpor(token, ulang, lanjutSetelah)
    end})
    table.insert(tombol, {"kelola atau hapus tanda tangan", function()
        TandaTangan.kelola(token, ulang, lanjutSetelah)
    end})
    PembuatAPK.dialogTombol("Pilih tanda tangan pribadi",
        "Ada " .. #daftar .. " tanda tangan pribadi. Pilih salah satu untuk membangun APK, atau tambah dan kelola tanda tangan.",
        tombol, {"kembali", ulang})
end

function TandaTangan.konfirmasi(fullName, token, o, kembali)
    local pesan = "Tanda tangan: " .. TandaTangan.label(o)
        .. "\nSidik jari SHA-256:\n" .. o.sidik
        .. "\n\nYang dikirim ke repo " .. fullName .. ":\n- " .. KS_JALUR .. " (keystore)\n- " .. PROP_JALUR
        .. " (alias dan sandi, dibaca alur kerja saat menandatangani)"
        .. "\n\nSiapa pun yang bisa membuka repo ini bisa melihat keduanya. Pastikan repo tetap privat dan jangan menambahkan kolaborator yang tidak Anda percaya."
    PembuatAPK.dialogTombol("Kirim tanda tangan ke repo", pesan, {
        {"kirim dan mulai pembangunan", function() TandaTangan.kirim(fullName, token, o, kembali) end},
    }, {"batal", function() TandaTangan.mulai(fullName, token, kembali) end})
end

function TandaTangan.kirim(fullName, token, o, kembali)
    local ok, ks = pcall(function() return bacaBerkasKeBytes(TandaTangan.berkasKunci(o.id)) end)
    if not ok or ks == nil then
        PembuatAPK.tampilError("Berkas tanda tangan tidak terbaca",
            "Salinan keystore di dalam aplikasi tidak ditemukan atau rusak:\n" .. tostring(ks)
            .. "\n\nBuat tanda tangan baru di menu Tanda tangan pribadi.", kembali)
        return
    end
    local prop = String("alias=" .. o.alias .. "\nsandi=" .. o.sandi .. "\n").getBytes("UTF-8")
    local ulang = function() TandaTangan.kirim(fullName, token, o, kembali) end

    -- Dua berkas dikirim dengan [skip ci] agar tidak memicu pembangunan sendiri; pembangunan dimulai sekali
    -- oleh bangunUlang setelah semuanya terpasang (termasuk alur kerja yang mendukung tanda tangan pribadi).
    TandaTangan.tulisBerkas(fullName, token, PROP_JALUR, prop, "Simpan sandi tanda tangan pribadi" .. SKIP_CI, ulang, function()
        TandaTangan.tulisBerkas(fullName, token, KS_JALUR, ks, "Simpan tanda tangan pribadi" .. SKIP_CI, ulang, function()
            TandaTangan.pastikanAlurKerja(fullName, token, kembali, function()
                Toast.makeText(service, "Tanda tangan pribadi terkirim ke repo.", Toast.LENGTH_SHORT).show()
                PembuatAPK.bangunUlang(fullName, token, kembali)
            end)
        end)
    end)
end

function PembuatAPK.pastikanWorkflow(fullName, token, kembali, lanjut, idAwal)
    local jalur = ".github/workflows/" .. NAMA_ALUR_KERJA
    local endpoint = "https://api.github.com/repos/" .. fullName .. "/contents/" .. jalur
    kirimPermintaanGitHub("GET", endpoint, token, nil, function(ada, res)
        if ada then
            lanjut(false)
            return
        end
        if not tostring(res):find("404") then
            PembuatAPK.tampilError("Gagal memeriksa alur kerja APK",
                "Proyek: " .. fullName .. "\n\n" .. tostring(res), kembali)
            return
        end
        PembuatAPK.dialogTombol("Alur kerja APK belum ada",
            "Repo ini belum memiliki berkas " .. jalur .. " yang membangun APK.\n\nSyarat: isi repo adalah proyek Android Gradle dengan modul bernama app (app/build.gradle).\n\nTekan tombol di bawah untuk memasang alur kerja, lalu GitHub akan membangun APK otomatis.",
            {
                {"pasang alur kerja dan bangun APK", function()
                    local slug = buatSlug(fullName:match("[^/]+$") or "aplikasi")
                    if slug == "" then slug = "aplikasi" end
                    local isi = isiTemplat(TEMPLAT.workflowLengkap, {NAMA_APK = slug})
                    local payload = JSONObject()
                    payload.put("message", "Pasang alur kerja bangun APK")
                    payload.put("content", Base64.encodeToString(String(isi).getBytes("UTF-8"), Base64.NO_WRAP))
                    kirimPermintaanGitHub("PUT", endpoint, token, payload.toString(), function(ok2, res2)
                        if ok2 then
                            lanjut(true)
                        else
                            local info = "Proyek: " .. fullName .. "\n\n" .. tostring(res2)
                            if tostring(res2):lower():find("workflow") then
                                info = info .. "\n\nToken GitHub perlu izin workflow. Buat token baru dengan izin repo dan workflow."
                            end
                            PembuatAPK.tampilError("Gagal memasang alur kerja", info, kembali)
                        end
                    end)
                end},
            }, {"batal", kembali})
    end, true)
end

function PembuatAPK.bangunUlang(fullName, token, kb)
    local kembali = tetapkanKembali(fullName, token, kb)
    PembuatAPK.ambilIdRunTerakhir(fullName, token, function(idAwal)
        PembuatAPK.pastikanWorkflow(fullName, token, kembali, function(baruDipasang)
            if baruDipasang then
                -- Memasang alur kerja sudah memicu pembangunan otomatis (push), cukup dipantau.
                PembuatAPK.pantau(fullName, token, kembali, idAwal)
                return
            end
            kirimPermintaanGitHub("GET", "https://api.github.com/repos/" .. fullName, token, nil, function(ok, res)
                if not ok then
                    PembuatAPK.tampilError("Gagal membaca proyek",
                        "Proyek: " .. fullName .. "\n\n" .. tostring(res), kembali,
                        {{"coba lagi", function() PembuatAPK.bangunUlang(fullName, token, kembali) end}})
                    return
                end
                local cabang = JSONObject(res).optString("default_branch", "main")
                local payload = JSONObject()
                payload.put("ref", cabang)
                local endpoint = "https://api.github.com/repos/" .. fullName .. "/actions/workflows/" .. NAMA_ALUR_KERJA .. "/dispatches"
                kirimPermintaanGitHub("POST", endpoint, token, payload.toString(), function(ok2, res2)
                    if ok2 then
                        if service.speak then service.speak("Pembangunan APK dimulai.") end
                        PembuatAPK.pantau(fullName, token, kembali, idAwal)
                    else
                        local info = "Proyek: " .. fullName .. "\nCabang: " .. cabang .. "\n\n" .. tostring(res2)
                        if tostring(res2):find("workflow_dispatch") then
                            info = info .. "\n\nAlur kerja di repo ini belum memiliki pemicu workflow_dispatch, sehingga tidak bisa dijalankan manual."
                        end
                        PembuatAPK.tampilError("Gagal memulai pembangunan APK", info, kembali,
                            {{"coba lagi", function() PembuatAPK.bangunUlang(fullName, token, kembali) end}})
                    end
                end)
            end)
        end, idAwal)
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
        elseif which==2 then TandaTangan.mulai(fullName,token)
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

local sudahPindaiSesi = false

-- cari repo yang punya alur kerja bangun-apk.yml dan tambahkan ke daftar aplikasi; selesai(jumlahBaru, galat)
function PembuatAPK.pindaiAplikasi(token, paksa, selesai)
    muatSemuaRepo(token, paksa, function(ok, arr)
        if not ok then
            selesai(0, tostring(arr))
            return
        end
        local nama = {}
        for i = 0, arr.length() - 1 do
            local r = arr.getJSONObject(i)
            if not r.optBoolean("archived", false) then
                local fn = tostring(r.optString("full_name", ""))
                if fn ~= "" then table.insert(nama, fn) end
            end
        end
        local total = #nama
        if total == 0 then
            selesai(0, nil)
            return
        end

        local batal = false
        local selesaiDipanggil = false
        local progress = ProgressDialog(service)
        progress.setTitle("Mencari proyek aplikasi")
        progress.setMessage("Memeriksa GitHub (0/" .. total .. ")...")
        progress.setCancelable(true)
        progress.setOnCancelListener(DialogInterface.OnCancelListener{
            onCancel = function() batal = true end
        })
        progress.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
        progress.show()

        local ditemukan = {}
        local idx, sudah = 0, 0

        local function akhiri()
            if selesaiDipanggil then return end
            selesaiDipanggil = true
            pcall(function() progress.dismiss() end)
            local lokal = ambilDaftarAplikasi()
            local ada = {}
            for _, n in ipairs(lokal) do ada[n] = true end
            local baru = 0
            for _, f in ipairs(ditemukan) do
                if not ada[f] then
                    tambahKeDaftarAplikasi(f)
                    baru = baru + 1
                end
            end
            selesai(baru, nil)
        end

        -- paling banyak 5 pemeriksaan sekaligus agar tidak kena batas laju GitHub
        local function pompa()
            if batal then
                akhiri()
                return
            end
            if idx >= total then return end
            idx = idx + 1
            local fn = nama[idx]
            kirimPermintaanGitHub("GET",
                "https://api.github.com/repos/" .. fn .. "/contents/.github/workflows/" .. NAMA_ALUR_KERJA,
                token, nil, function(ok2, res2)
                    if ok2 then table.insert(ditemukan, fn) end
                    sudah = sudah + 1
                    pcall(function() progress.setMessage("Memeriksa GitHub (" .. sudah .. "/" .. total .. ")...") end)
                    if sudah < total then
                        pompa()
                    else
                        akhiri()
                    end
                end, true)
        end
        for _ = 1, math.min(5, total) do pompa() end
    end)
end

function PembuatAPK.daftar(token, lewatiPindai)
    if not lewatiPindai and not sudahPindaiSesi then
        sudahPindaiSesi = true
        PembuatAPK.pindaiAplikasi(token, false, function(baru, galat)
            if galat then
                Toast.makeText(service, "Gagal memeriksa GitHub: " .. galat, Toast.LENGTH_LONG).show()
            elseif baru > 0 then
                local pesan = "Ditemukan " .. baru .. " proyek aplikasi dari GitHub."
                if service.speak then service.speak(pesan) end
                Toast.makeText(service, pesan, Toast.LENGTH_LONG).show()
            end
            PembuatAPK.daftar(token, true)
        end)
        return
    end

    local daftar = ambilDaftarAplikasi()
    local tombol = {}
    for _, nama in ipairs(daftar) do
        table.insert(tombol, {nama, function() PembuatAPK.menuAplikasi(nama, token) end})
    end
    table.insert(tombol, {"Buat aplikasi baru", function() PembuatAPK.formAplikasiBaru(token) end})
    table.insert(tombol, {"Segarkan daftar (cari di GitHub)", function()
        PembuatAPK.pindaiAplikasi(token, true, function(baru, galat)
            if galat then
                Toast.makeText(service, "Gagal memeriksa GitHub: " .. galat, Toast.LENGTH_LONG).show()
            elseif baru > 0 then
                Toast.makeText(service, "Ditemukan " .. baru .. " proyek aplikasi dari GitHub.", Toast.LENGTH_LONG).show()
            else
                Toast.makeText(service, "Tidak ada proyek aplikasi baru.", Toast.LENGTH_SHORT).show()
            end
            PembuatAPK.daftar(token, true)
        end)
    end})
    local pesan = (#daftar == 0) and "Belum ada proyek aplikasi." or ("Ada " .. #daftar .. " proyek aplikasi. Pilih salah satu untuk mengelola.")
    if service.speak then service.speak("Aplikasi saya. " .. pesan) end
    PembuatAPK.dialogTombol("Aplikasi saya", pesan, tombol, {"kembali", function() PembuatAPK.menu(token) end})
end

PembuatAPK.menu = function(token)
    local items={
        "1. Buat aplikasi APK Android lengkap",
        "2. Aplikasi saya",
        "3. Mulai build ulang",
        "4. Lihat status build",
        "5. Unduh APK/AAB dan artifact",
        "6. Tanda tangan pribadi",
        "7. Panduan tanda tangan APK",
        "8. Panduan fitur GitHub Actions",
        "9. Panduan signing dan GitHub Secrets"
    }
    local b=AlertDialog.Builder(service); b.setTitle("Pusat Pembuatan APK Android")
    b.setItems(items,DialogInterface.OnClickListener{onClick=function(_,which)
        if which==0 then PembuatAPK.formAplikasiBaru(token)
        elseif which==1 then PembuatAPK.daftar(token)
        elseif which==2 then PembuatAPK.daftar(token)
        elseif which==3 then PembuatAPK.daftar(token)
        elseif which==4 then PembuatAPK.daftar(token)
        elseif which==5 then
            TandaTangan.kelola(token, function() PembuatAPK.menu(token) end)
        elseif which==6 then
            PembuatAPK.dialogTombol("Panduan tanda tangan APK",
                "Saat memilih 'Mulai pembangunan APK', terdapat 2 opsi tanda tangan:\n\n"
                .. "1. Tanda tangan bawaan GitHub:\n"
                .. "APK dibangun versi debug menggunakan kunci sementara milik runner GitHub. "
                .. "Kuncinya berganti di setiap pembangunan baru, sehingga aplikasi yang sudah terpasang "
                .. "harus dicopot terlebih dahulu jika ingin memasang APK pembaruan berikutnya.\n\n"
                .. "2. Tanda tangan pribadi:\n"
                .. "APK dibangun versi rilis menggunakan sertifikat milik Anda (.tanda-tangan/kunci.p12) "
                .. "dan sandi (.tanda-tangan/sandi.properties). Hanya berlaku untuk repositori privat. "
                .. "Aplikasi yang terpasang di perangkat selalu bisa diperbarui tanpa perlu dicopot.",
                {{"buka repositori", function() bukaBrowser("https://github.com/settings/repositories") end, tetap = true}},
                {"kembali", function() PembuatAPK.menu(token) end})
        elseif which==7 then
            tampilDialog("Fitur GitHub Actions","Workflow dapat menjalankan beberapa job, matrix build, pemeriksaan Lint, Unit Test, instrumentation test, cache, artifact, release, dan attestation.",
                {"mengerti",function() PembuatAPK.menu(token) end})
        elseif which==8 then
            tampilDialog("Signing Release","Untuk signing Release yang aman, simpan keystore sebagai GitHub Secret KEYSTORE_BASE64 dan password sebagai KEYSTORE_PASSWORD, KEY_ALIAS, serta KEY_PASSWORD. Jangan memasukkan password ke source code.",
                {"buka secrets",function() bukaBrowser("https://github.com/settings/repositories") end},nil,{"kembali",function() PembuatAPK.menu(token) end})
        end
    end})
    b.setNegativeButton("kembali",DialogInterface.OnClickListener{onClick=function() menuUtama() end})
    local d=b.create(); d.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY); d.show(); aturTombolHurufKecil(d,nil,"kembali",nil)
end

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
                tampilDialog("Keluar akun?", "Token akan dihapus dari aplikasi ini.",
                    {"keluar", function()
                        prefs.edit().remove(KEY_TOKEN).apply()
                        batalkanCacheRepo()
                        if service.speak then service.speak("Token dihapus. Anda keluar.") end
                        Toast.makeText(service, "Anda telah keluar.", Toast.LENGTH_SHORT).show()
                        tampilkanDialogLogin()
                    end}, nil,
                    {"batal", function() menuUtama() end})
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

tampilkanDialogLogin = function(tokenAwal)
    local layout = LinearLayout(service)
    layout.setOrientation(LinearLayout.VERTICAL)
    layout.setPadding(40, 20, 40, 10)

    local input = EditText(service)
    input.setHint("Tempel token di sini")
    input.setSingleLine(true)
    if tokenAwal and tokenAwal ~= "" then input.setText(tokenAwal) end
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
            -- token diperiksa langsung ke GitHub sebelum disimpan
            kirimPermintaanGitHub("GET", "https://api.github.com/user", t, nil, function(ok, res)
                if not ok then
                    if service.speak then service.speak("Token ditolak.") end
                    Toast.makeText(service, "Token ditolak. " .. tostring(res), Toast.LENGTH_LONG).show()
                    tampilkanDialogLogin(t)
                    return
                end
                prefs.edit().putString(KEY_TOKEN, t).apply()
                local nama = "pengguna"
                pcall(function() nama = tostring(JSONObject(res).optString("login", "pengguna")) end)
                if service.speak then service.speak("Berhasil masuk sebagai " .. nama .. ".") end
                Toast.makeText(service, "Berhasil masuk sebagai " .. nama .. ".", Toast.LENGTH_SHORT).show()
                menuUtama()
            end)
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