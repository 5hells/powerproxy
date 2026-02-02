(ns schedule
  (:gen-class)
  (:require
   [clj-http.client :as http]
   [cheshire.core :as json]
   [compojure.core :refer [defroutes GET POST]]
   [compojure.route :as route]
   [ring.adapter.jetty :as jetty]
   [ring.util.response :as response]
   [clojure.string :as str]
   [hickory.core :as hickory]
   [hickory.select :as s]))

(defn parse-class-cell [cell-content]
  "Parse a class cell content into structured data.
   Input: 'Class Name<br>Teacher Name<br>Room<br>Start Time - End Time'
   Output: {:name 'Class Name' :teacher 'Teacher Name' :room 'Room' :time 'Start Time - End Time'}"
  (when cell-content
    (let [parts (str/split cell-content #"<br>")
          clean-parts (map #(str/replace % #"&nbsp;" "") parts)]
      (when (>= (count clean-parts) 4)
        {:name (-> (first clean-parts) str/trim (str/replace #"\s+" " ") str/trim)
         :teacher (-> (second clean-parts) str/trim (str/replace #"\s+" " ") str/trim)
         :room (-> (nth clean-parts 2) str/trim (str/replace #"\s+" " ") str/trim)
         :time (-> (nth clean-parts 3) str/trim (str/replace #"\s+" " ") str/trim)}))))

(defn extract-text [element]
  "Extract text content from hickory element, preserving <br> tags for parsing"
  (if (string? element)
    (str/trim element)
    (let [tag (:tag element)
          content (:content element)]
      (cond
        (= tag :img) ""
        (= tag :br) "<br>"
        (seq content) (apply str (map extract-text content))
        :else ""))))

(defn extract-header-text [element]
  "Extract header text, cleaning up HTML tags"
  (let [raw-text (extract-text element)]
    (-> raw-text
        (str/replace #"<[^>]+>" "")
        (str/replace #"^\s*<b>" "")
        (str/replace #"</b>\s*$" "")
        str/trim)))

(defn extract-date-from-name [name-attr]
  "Extract date string from cell name attribute like 'attCell20260202' -> '02/02/2026'"
  (when name-attr
    (when-let [[_ year month day] (re-find #"attCell(\d{4})(\d{2})(\d{2})" name-attr)]
      (str month "/" day "/" year))))

(defn parse-schedule-table [table-element]
  "Parse the schedule table into structured data grouped by day.
   Returns a map with day strings as keys and vectors of class maps as values.
   Uses the 'name' attribute on cells to determine which day a class belongs to,
   avoiding issues with rowspan shifting cell indices."
  (let [rows (s/select (s/tag :tr) table-element)
        header-row (first rows)
        data-rows (rest rows)

        ;; Extract header info: day name and date pairs
        date-headers (s/select (s/class "scheduleHeader") header-row)
        header-texts (map #(extract-header-text %) date-headers)
        ;; Build a map from date (MM/DD/YYYY) to full header text (e.g., "Monday02/02/2026")
        date-to-header (into {} (for [h header-texts
                                       :let [[_ day date] (re-find #"^([A-Za-z]+)(.+)$" h)]
                                       :when date]
                                   [date h]))

        schedule-data (atom {})
        seen-classes (atom #{})]

    (doseq [row data-rows]
      (let [cells (s/select (s/tag :td) row)]
        (doseq [cell cells]
          (let [cell-class (get-in cell [:attrs :class] "")
                cell-name (get-in cell [:attrs :name])]
            (when (and cell-class
                       (re-matches #"scheduleClass\d+.*" cell-class)
                       cell-name)
              (let [cell-date (extract-date-from-name cell-name)
                    header-key (get date-to-header cell-date)]
                (when header-key
                  (let [cell-content (extract-text cell)]
                    (when-let [class-data (parse-class-cell cell-content)]
                      (let [class-key [header-key (:name class-data) (:time class-data)]]
                        (when-not (@seen-classes class-key)
                          (swap! seen-classes conj class-key)
                          (swap! schedule-data update header-key (fnil conj []) class-data))))))))))))

    @schedule-data))

(defn normalize-schedule [schedule-map]
  "Normalize the schedule map into a list of day maps with name, date, and classes."
  (for [[key classes] schedule-map]
    (let [[_ day date] (re-find #"^([A-Za-z]+)(.+)$" key)
          normalized-classes (map (fn [class]
                                    (let [[start end] (str/split (:time class) #" - ")]
                                      (-> class
                                          (update :name str/trim)
                                          (assoc :start (str/trim start) :end (str/trim end))
                                          (dissoc :time))))
                                  classes)]
      {:name day :date date :classes normalized-classes})))

(defn fetch-schedule
  "Fetch the schedule page from PowerSchool and parse it into structured data."
  [cookies ps-base]
  (let [schedule-url (str "https://" ps-base ".powerschool.com/guardian/myschedule.html")
        response (http/get schedule-url
                           {:headers {"Cookie" (str/join "; " (map #(str (key %) "=" (val %)) cookies))
                                      "User-Agent" "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/85.0.4183.102 Safari/537.36"
                                      "Accept" "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"
                                      "Accept-Language" "en-US,en;q=0.9"}
                            :encoding "UTF-8"
                            :as :text})
        html-body (:body response)
        parsed-html (hickory/parse html-body)
        hickory-doc (hickory/as-hickory parsed-html)
        table (first (s/select (s/and (s/tag :table) (s/id "tableStudentSchedMatrix")) hickory-doc))]
    (if table
      (normalize-schedule (parse-schedule-table table))
      (throw (Exception. "Schedule table not found in the HTML response")))))


(defn parse-attendance-totals [html-string]
  (let [parsed-html (hickory/parse html-string)
        hickory-doc (hickory/as-hickory parsed-html)

        att-total nil ; Not used, as it's text "Attendance Totals"

        term-abs-total (when-let [elem (first (filter #(re-find #"attendancedatesall.*codes=\*abs" (get-in % [:attrs :href] "")) (s/select (s/tag :a) hickory-doc)))]
                         (let [text (extract-text elem)]
                           (when (and text (not (str/blank? text)) (re-matches #"\d+" text))
                             (Integer/parseInt text))))

        term-tar-total (when-let [elem (first (filter #(re-find #"attendancedatesall.*codes=\*tar" (get-in % [:attrs :href] "")) (s/select (s/tag :a) hickory-doc)))]
                         (let [text (extract-text elem)]
                           (when (and text (not (str/blank? text)) (re-matches #"\d+" text))
                             (Integer/parseInt text))))

        gpa (when-let [gpa-td (first (filter #(re-find #"Current Simple GPA" (extract-text %)) (s/select (s/tag :td) hickory-doc)))]
              (when-let [text (extract-text gpa-td)]
                (re-find #"\d+\.\d+" text)))]
    {:attendance-total att-total
     :term-absences term-abs-total
     :term-tardies term-tar-total
     :gpa (when gpa (Double/parseDouble gpa))}))

(defn fetch-attendance-totals
  "Fetch the attendance and GPA page from PowerSchool and parse totals."
  [cookies ps-base]
  (let [attendance-url (str "https://" ps-base ".powerschool.com/guardian/home.html")
        response (http/get attendance-url
                           {:headers {"Cookie" (str/join "; " (map #(str (key %) "=" (val %)) cookies))
                                      "User-Agent" "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/85.0.4183.102 Safari/537.36"
                                      "Accept" "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"
                                      "Accept-Language" "en-US,en;q=0.9"}
                            :encoding "UTF-8"
                            :as :text})
        html-body (:body response)]
    (parse-attendance-totals html-body)))

(defn parse-class-grades [class-row]
  "Parse a single class row from the grades table to extract grade and attendance data.
   Returns a map with :class-name, :s2, :p1, :s1, :absences, :tardies
   Table structure: Exp (0) | Last Week (1-5) | This Week (6-10) | Course (11) | S2 (12) | P1 (13) | S1 (14) | Absences (15) | Tardies (16)"
  (when (map? class-row)
    (let [cells (s/select (s/tag :td) class-row)
          cell-count (count cells)]
      (when (>= cell-count 17)
        (let [; Extract class name from the Course cell (column 11)
              class-cell (nth cells 11)
              ; Get the text content and extract the class name (before the first <br> or link)
              raw-text (extract-text class-cell)
              class-name (when raw-text
                           (let [cleaned (-> raw-text
                                           (str/replace #"<br>.*" "")  ; Remove everything after <br>
                                           (str/replace #"&nbsp;" " ")
                                           str/trim
                                           (str/replace #"\s+" " ")  ; Replace multiple spaces with single space
                                           str/trim)]
                             (when-not (str/blank? cleaned)
                               cleaned)))
              
              ; Extract semester grades (S2, P1, S1) - columns 12, 13, 14
              s2-cell (nth cells 12)
              p1-cell (nth cells 13)
              s1-cell (nth cells 14)
              
              ; Extract attendance data - columns 15, 16
              abs-cell (nth cells 15)
              tar-cell (nth cells 16)
              
              ; Helper to extract letter grade (like "C+", "A", "B-") or numeric percentage
              extract-grade (fn [cell]
                (when-let [text (extract-text cell)]
                  (let [cleaned (str/trim text)]
                    ; Try to find letter grade first (A+, A, A-, B+, etc.)
                    (if-let [[_ grade] (re-find #"([A-F][+-]?)" cleaned)]
                      grade
                      ; Otherwise look for numeric percentage
                      (when-let [[_ num] (re-find #"(\d+\.?\d*)" cleaned)]
                        num)))))
              
              ; Helper to extract numeric value from links like attendance counts
              extract-number (fn [cell]
                (when-let [text (extract-text cell)]
                  (when-let [[_ num] (re-find #"(\d+)" text)]
                    (Integer/parseInt num))))]
          
          (when (and class-name (not (str/blank? class-name)))
            {:class-name class-name
             :s2 (extract-grade s2-cell)
             :p1 (extract-grade p1-cell)
             :s1 (extract-grade s1-cell)
             :absences (or (extract-number abs-cell) 0)
             :tardies (or (extract-number tar-cell) 0)}))))))

(defn fetch-class-grades
  "Fetch the grades and attendance page from PowerSchool with per-class breakdown."
  [cookies ps-base]
  (let [grades-url (str "https://" ps-base ".powerschool.com/guardian/home.html")
        response (http/get grades-url
                           {:headers {"Cookie" (str/join "; " (map #(str (key %) "=" (val %)) cookies))
                                      "User-Agent" "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/85.0.4183.102 Safari/537.36"
                                      "Accept" "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"
                                      "Accept-Language" "en-US,en;q=0.9"}
                            :encoding "UTF-8"
                            :as :text})
        html-body (:body response)
        parsed-html (hickory/parse html-body)
        hickory-doc (hickory/as-hickory parsed-html)
        
        ; Find the grades table by class or first table as fallback
        grade-table (try
                      (when (map? hickory-doc)
                        (or (first (s/select (s/and (s/tag :table) (s/class "linkDescList")) hickory-doc))
                            (first (s/select (s/tag :table) hickory-doc))))
                      (catch Exception e
                        (println "Error selecting grade table:" e)
                        nil))
        grade-rows (try
                     (if (and grade-table (map? grade-table)) 
                       (rest (s/select (s/tag :tr) grade-table)) 
                       [])
                     (catch Exception e
                       (println "Error selecting grade rows:" e)
                       []))
        
        ; Parse all class grades
        class-grades (try
                       (into {} (keep (fn [row]
                                        (try
                                          (when (and row (map? row))
                                            (when-let [grade-data (parse-class-grades row)]
                                              [(:class-name grade-data) (dissoc grade-data :class-name)]))
                                          (catch Exception e
                                            (println "Error parsing class grade row:" e)
                                            nil)))
                                      grade-rows))
                       (catch Exception e
                         (println "Error building class grades map:" e)
                         {}))]
    
    {:classes class-grades}))