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
import "org.json.JSONObject"
import "org.json.JSONArray"

local mainHandler = Handler(Looper.getMainLooper())

-- Pengaturan Versi & Tautan Skrip Pembaruan (Tetap versi 1.2)
local VERSI_SAAT_INI = "1.2"
local URL_RAW_SCRIPT = "https://raw.githubusercontent.com/novanblind/Pengelola-GitHub-pribadi/main/github.lua"

-- Jalur berkas skrip saat ini untuk pembaruan otomatis
local infoScript = debug.getinfo(1, "S")
local JALUR_BERKAS_SCRIPT = (infoScript and infoScript.source and infoScript.source:sub(1, 1) == "@") and infoScript.source:sub(2) or ""

-- Pengaturan nama SharedPreferences dan kunci unik
local PREF_NAME = "github_acc_manager_exclusive_unique_cfg"
local KEY_TOKEN = "key_github_user_pat_unique"
local prefs = service.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)

local sudahCekOtomatis = false

-- Deklarasi fungsi navigasi bertingkat
local menuUtama, tampilkanDialogLogin
local buatRepoDialog, tambahFileRepoDialog, unggahDariMemoriHPDialog
local daftarRepoSayaDialog, cariRepoDialog, kelolaRepoPilihanDialog, ubahPrivasiRepoDialog
local bukaDirektoriRepoDialog, menuAksiFile, formEditIsiBerkas, gantiNamaRepoDialog, hapusRepoDialog
local cekPembaruan, prosesDownloadPembaruan, aktifkanGitHubPagesOtomatis

-- Tautan otomatis pembuatan token dengan izin repo dan delete_repo
local URL_GENERATE_TOKEN = "https://github.com/settings/tokens/new?description=Aksesibilitas+Android&scopes=repo,delete_repo"

-- Fungsi mengambil tanggal/waktu perubahan terakhir dari repositori
local function ambilWaktuTerakhirEdit(repoObj)
  local pushed = repoObj.optString("pushed_at", "")
  local updated = repoObj.optString("updated_at", "")
  return (pushed > updated) and pushed or updated
end

-- Fungsi format ukuran berkas
local function formatUkuranBerkas(bytes)
  if bytes < 1024 then
    return bytes .. " B"
  elseif bytes < 1024 * 1024 then
    return string.format("%.1f KB", bytes / 1024)
  else
    return string.format("%.1f MB", bytes / (1024 * 1024))
  end
end

-- Fungsi membaca berkas lokal ke Base64
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

-- Fungsi penonaktif teks kapital bawaan Android (memaksa huruf kecil murni)
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

-- Fungsi pembanding versi
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

-- Fungsi menyimpan kode pembaruan
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

-- Pemasangan pembaruan otomatis
prosesDownloadPembaruan = function(kodeBaru)
  local progress = ProgressDialog(service)
  progress.setTitle("Mengunduh pembaruan")
  progress.setMessage("Sedang memasang skrip...")
  progress.setCancelable(false)
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

-- Fungsi periksa versi baru
cekPembaruan = function(manual)
  local progress
  if manual then
    progress = ProgressDialog(service)
    progress.setTitle("Periksa versi baru")
    progress.setMessage("Memeriksa ke server GitHub...")
    progress.setCancelable(false)
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

-- Fungsi buka URL ke browser
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

-- Fungsi salin ke clipboard
local function salinKeClipboard(label, teks)
  local clipboard = service.getSystemService(Context.CLIPBOARD_SERVICE)
  local clip = ClipData.newPlainText(label, teks)
  clipboard.setPrimaryClip(clip)
  if service.speak then service.speak(label .. " disalin.") end
  Toast.makeText(service, label .. " disalin!", Toast.LENGTH_SHORT).show()
end

-- Fungsi bagikan tautan via Share Android
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

-- Permintaan HTTP GitHub API
local function kirimPermintaanGitHub(metode, endpoint, token, jsonBody, onSelesai, diam)
  local progress
  if not diam then
    progress = ProgressDialog(service)
    progress.setTitle("Menghubungkan")
    progress.setMessage("Sedang memproses...")
    progress.setCancelable(false)
    progress.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    progress.show()
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

      mainHandler.post(Runnable{
        run = function()
          if progress then
            pcall(function() progress.dismiss() end)
          end
          onSelesai(ok, res)
        end
      })
    end
  }).start()
end

-- Aktivasi GitHub Pages otomatis
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
-- 1. DAFTAR & PENCARIAN REPOSITORI (DIURUTKAN TERAKHIR DIEDIT)
-- ==========================================================
daftarRepoSayaDialog = function(token)
  -- Meminta data repositori langsung terurut berdasarkan updated secara menurun (desc)
  local endpoint = "https://api.github.com/user/repos?sort=updated&direction=desc&per_page=100&affiliation=owner"
  kirimPermintaanGitHub("GET", endpoint, token, nil, function(ok, res)
    if not ok then
      Toast.makeText(service, "Gagal memuat: " .. tostring(res), Toast.LENGTH_LONG).show()
      return
    end

    local arr = JSONArray(res)
    local total = arr.length()
    if total == 0 then
      if service.speak then service.speak("Belum ada repositori.") end
      Toast.makeText(service, "Belum ada repositori.", Toast.LENGTH_SHORT).show()
      menuUtama()
      return
    end

    local repoDataList = {}
    for i = 0, total - 1 do
      table.insert(repoDataList, arr.getJSONObject(i))
    end

    -- Mengurutkan repositori: yang terakhir diedit/diperbarui tampil paling atas
    table.sort(repoDataList, function(a, b)
      return ambilWaktuTerakhirEdit(a) > ambilWaktuTerakhirEdit(b)
    end)

    local listItems = {}
    for i, item in ipairs(repoDataList) do
      local nama = item.optString("name", "")
      local status = item.optBoolean("private", false) and "[privat]" or "[publik]"
      table.insert(listItems, string.format("%d. %s %s", i, nama, status))
    end

    if service.speak then service.speak("Ditemukan " .. total .. " repositori.") end

    local b = AlertDialog.Builder(service)
    b.setTitle("Repositori saya (" .. total .. ")")
    b.setItems(listItems, DialogInterface.OnClickListener{
      onClick = function(dialog, which)
        kelolaRepoPilihanDialog(repoDataList[which + 1], token)
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

-- Dialog Pencarian Repositori Cepat (Juga Terurut dari Terakhir Diedit)
cariRepoDialog = function(token)
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)
  layout.setPadding(40, 20, 40, 10)

  local input = EditText(service)
  input.setHint("Ketik nama repositori...")
  input.setSingleLine(true)
  layout.addView(input)

  local scroll = ScrollView(service)
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

        if #hasilData == 0 then
          if service.speak then service.speak("Tidak ada repositori yang cocok.") end
          Toast.makeText(service, "Repositori tidak ditemukan.", Toast.LENGTH_SHORT).show()
          cariRepoDialog(token)
          return
        end

        -- Urutkan hasil pencarian: yang terakhir diedit paling atas
        table.sort(hasilData, function(a, b)
          return ambilWaktuTerakhirEdit(a) > ambilWaktuTerakhirEdit(b)
        end)

        local hasilItems = {}
        for i, item in ipairs(hasilData) do
          local nama = item.optString("name", "")
          local status = item.optBoolean("private", false) and "[privat]" or "[publik]"
          table.insert(hasilItems, string.format("%d. %s %s", i, nama, status))
        end

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
  diag.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
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

-- ==========================================================
-- 3. UBAH PRIVASI REPOSITORI (PUBLIK <-> PRIVAT)
-- ==========================================================
ubahPrivasiRepoDialog = function(repoObj, token)
  local namaRepo = repoObj.optString("name", "")
  local fullName = repoObj.optString("full_name", "")
  local isPrivate = repoObj.optBoolean("private", false)
  local targetStatusTeks = isPrivate and "publik" or "privat"

  local b = AlertDialog.Builder(service)
  b.setTitle("Ubah privasi repo")
  b.setMessage("Status saat ini: " .. (isPrivate and "Privat" or "Publik") .. ".\n\nApakah Anda yakin ingin mengubah repositori ini menjadi " .. targetStatusTeks .. "?")
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

-- ==========================================================
-- 4. UNGGAH BERKAS DARI MEMORI HP (FILE PICKER)
-- ==========================================================
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
          local terpilih = item.file

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

          local scrollK = ScrollView(service)
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
      end)
    end
  end

  b.setNegativeButton("kembali", DialogInterface.OnClickListener{
    onClick = function() kelolaRepoPilihanDialog(repoObj, token) end
  })
  local diag = b.create()
  diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
  diag.show()
  aturTombolHurufKecil(diag, nil, "kembali", nil)
end

-- ==========================================================
-- 5. HAPUS REPOSITORI
-- ==========================================================
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

-- ==========================================================
-- 6. GANTI NAMA REPOSITORI
-- ==========================================================
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

  local scroll = ScrollView(service)
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

-- ==========================================================
-- 7. PENJELAJAH BERKAS & FOLDER
-- ==========================================================
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

-- ==========================================================
-- 8. MENU AKSI BERKAS SPESIFIK
-- ==========================================================
menuAksiFile = function(fullName, fileData, token, currentPath, repoObj)
  local opsiFile = {
    "1. Salin tautan raw (updater)",
    "2. Edit berkas",
    "3. Salin tautan web",
    "4. Bagikan tautan raw",
    "5. Hapus berkas"
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
        salinKeClipboard("Tautan web", fileData.html_url)
      elseif which == 3 then
        bagikanTautan("Berkas raw: " .. fileData.name, fileData.download_url)
      elseif which == 4 then
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

-- ==========================================================
-- 9. EDITOR TEKS BERKAS
-- ==========================================================
formEditIsiBerkas = function(repo, path, sha, isiAwal, token, onSuccess, onBatal)
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)
  layout.setPadding(40, 20, 40, 10)

  local editor = EditText(service)
  editor.setText(isiAwal)
  editor.setMinLines(6)
  layout.addView(editor)

  local scroll = ScrollView(service)
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
-- 10. PEMBUATAN REPOSITORI BARU
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

  local scroll = ScrollView(service)
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
      payload.put("auto_init", true)

      kirimPermintaanGitHub("POST", "https://api.github.com/user/repos", token, payload.toString(), function(ok, res)
        if ok then
          local obj = JSONObject(res)
          local fullName = obj.optString("full_name", "")
          local defaultBranch = obj.optString("default_branch", "main")
          local htmlUrl = obj.optString("html_url", "")

          mainHandler.postDelayed(Runnable{
            run = function()
              aktifkanGitHubPagesOtomatis(fullName, defaultBranch, token, function(suksesPages, infoPages)
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
              end)
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

-- ==========================================================
-- 11. TAMBAH BERKAS BARU (KETIK MANUAL)
-- ==========================================================
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

  local scroll = ScrollView(service)
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
-- 12. MENU UTAMA & LOGIN
-- ==========================================================
menuUtama = function()
  local token = prefs.getString(KEY_TOKEN, "")
  if token == "" then
    tampilkanDialogLogin()
    return
  end

  if not sudahCekOtomatis then
    sudahCekOtomatis = true
    cekPembaruan(false)
  end

  local menuItems = {
    "1. Repositori saya",
    "2. Cari repositori",
    "3. Buat repositori baru",
    "4. Salin token saya",
    "5. Buat token di web",
    "6. Keluar akun",
    "7. Periksa versi baru"
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
        salinKeClipboard("Token GitHub", token)
      elseif which == 4 then
        bukaBrowser(URL_GENERATE_TOKEN)
      elseif which == 5 then
        prefs.edit().remove(KEY_TOKEN).apply()
        if service.speak then service.speak("Token dihapus. Anda keluar.") end
        Toast.makeText(service, "Anda telah keluar.", Toast.LENGTH_SHORT).show()
      elseif which == 6 then
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

  local scroll = ScrollView(service)
  scroll.setFillViewport(true)
  scroll.addView(layout)

  local b = AlertDialog.Builder(service)
  b.setTitle("Masuk akun GitHub")
  b.setMessage("Masukkan token GitHub Anda. Jika belum punya, tekan 'dapatkan token di web':")
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

  b.setNegativeButton("tutup", nil)

  local diag = b.create()
  diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
  diag.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
  diag.show()
  aturTombolHurufKecil(diag, "simpan token", "tutup", "dapatkan token di web")
end

menuUtama()
