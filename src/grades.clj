(ns grades
  (:gen-class)
  (:require
   [assignments :refer [extract-text-content]]
   [cheshire.core]
   [clj-http.client :as client]
   [clojure.string :as str]
   [hickory.core :as hickory]
   [hickory.select :as s]
   [etaoin.api :as etaoin]))

(defn cookies-to-header [cookies]
  "Convert cookies map to a Cookie header string."
  (if (nil? cookies)
    ""
    (try
      (let [cookie-pairs (keep (fn [[k v]]
                                 (when (and (not (nil? k))
                                            (not (nil? v))
                                            (not= v "null"))
                                   (let [k-str (if (keyword? k) (name k) (str k))
                                         v-str (if (string? v) v (str v))]
                                     (str k-str "=" v-str))))
                               cookies)]
        (str/join "; " cookie-pairs))
      (catch Exception e
        (println "DEBUG: Cookie header generation failed:" (.getMessage e))
        ""))))

(defn fetch-grades-page [cookies ps-base]
  (try
    (when (nil? ps-base)
      (throw (Exception. "ps-base is null")))
    (when (nil? cookies)
      (throw (Exception. "cookies is null")))
    (when (empty? cookies)
      (throw (Exception. "cookies is empty")))

    (println "DEBUG: Fetching grades from ps-base=" ps-base)
    (println "DEBUG: Original cookies type=" (type cookies) " keys=" (if (map? cookies) (keys cookies) "not-a-map"))

    ;; Convert cookies to header string instead of passing as :cookies
    (let [cookie-header (cookies-to-header cookies)]
      (println "DEBUG: Cookie header length=" (count cookie-header))
      (when (empty? cookie-header)
        (throw (Exception. "No valid cookies after conversion")))

      (let [url (str "https://" ps-base ".powerschool.com/guardian/home.html")
            response (client/get url
                                 {:headers {"Cookie" cookie-header}
                                  :throw-exceptions false
                                  :follow-redirects true})]
        (println "DEBUG: Got response, status=" (:status response) " body type=" (type (:body response)))

        (if (nil? response)
          (throw (Exception. "No response from server"))
          (let [status (:status response)
                body (:body response)]
            (println "DEBUG: Response status=" status " body is nil?" (nil? body) " body is string?" (string? body))

            (when (or (nil? status) (>= status 400))
              (throw (Exception. (str "HTTP error: status " status))))

            (if (nil? body)
              (throw (Exception. "Response body is null"))
              (if (string? body)
                (do
                  ;; Check if we were redirected to the login page (authentication failed)
                  (when (str/includes? body "Student and Parent Sign In")
                    (throw (Exception. "Authentication failed - session expired or invalid cookies")))
                  (println "DEBUG: About to return body, type=" (type body) " length=" (count body))
                  body)
                (throw (Exception. (str "Response body is not a string: " (type body))))))))))
    (catch Exception e
      (println "DEBUG: Exception in fetch-grades-page:" (.getMessage e))
      (.printStackTrace e)
      (throw (Exception. (str "Failed to fetch grades page: " (.getMessage e)))))))

(defn extract-course-name
  "Extract just the course name from the course cell, ignoring teacher info and room."
  [element]
  (try
    (let [text (if (string? element) element (extract-text-content element))]
      ;; Remove everything after "Email" or common separators
      (let [cleaned (str/trim (first (str/split text #"(?i)Email|<br>|[\n\r]")))]
        (if (str/blank? cleaned)
          ""
          ;; Replace all whitespace (including non-breaking spaces) with single space
          (str/trim (str/replace cleaned #"\s+" " ")))))
    (catch Exception e
      (println "DEBUG: Error in extract-course-name:" (.getMessage e))
      "")))

(defn extract-grade-value [grade-text]
  (if (or (nil? grade-text) (str/blank? grade-text))
    nil
    (try
      (let [clean (str/trim (if (string? grade-text) grade-text (extract-text-content grade-text)))]
        ;; Handle cases like "[ i ]", "C+", "80", "C+80", "C+ 80", etc.
        (cond
          ;; Incomplete grade marker
          (str/includes? clean "[ i ]") "Incomplete"

          ;; Just a percentage
          (and (not (str/includes? clean " "))
               (re-matches #"\d+(\.\d+)?" clean))
          (try
            {:percentage (Double/parseDouble clean)}
            (catch Exception _ clean))

          ;; Letter grade and percentage together like "C+80"
          (re-matches #"[A-F][+-]?\d+(\.\d+)?" clean)
          (let [match (re-matches #"([A-F][+-]?)(\d+(?:\.\d+)?)" clean)]
            (if match
              {:letter-grade (second match)
               :percentage (Double/parseDouble (nth match 2))}
              clean))

          ;; Letter grade and percentage with space like "C+ 80"
          (re-matches #"[A-F][+-]?\s+\d+(\.\d+)?" clean)
          (let [parts (str/split clean #"\s+")]
            (if (>= (count parts) 2)
              (try
                {:letter-grade (first parts)
                 :percentage (Double/parseDouble (second parts))}
                (catch Exception _ clean))
              clean))

          ;; Just letter grade
          (re-matches #"[A-F][+-]?" clean)
          {:letter-grade clean}

          ;; Default case
          :else clean))
      (catch Exception e
        (println "DEBUG: Error in extract-grade-value:" (.getMessage e))
        nil))))

(defn safe-select [selector elem]
  "Safely apply a selector to an element, handling hickory errors."
  (try
    (s/select selector elem)
    (catch Exception e
      (println "Selector error: " (.getMessage e) " on element type: " (type elem))
      [])))

(defn parse-attendance-table [html]
  (try
    (println "DEBUG: parse-attendance-table called with html length=" (if (string? html) (count html) "not-string"))
    ;; Debug: show first 500 chars of HTML
    (println "DEBUG: HTML preview:" (if (string? html) (subs html 0 (min 500 (count html))) "not-string"))
    (when (or (nil? html) (not (string? html)))
      (throw (Exception. (str "HTML input invalid: " (type html)))))
    (println "DEBUG: About to parse HTML...")
    (let [dom (try
                (hickory/as-hickory (hickory/parse html))
                (catch Exception e
                  (println "DEBUG: hickory/parse failed:" (.getMessage e))
                  (.printStackTrace e)
                  (throw (Exception. (str "HTML parsing failed: " (.getMessage e))))))]
      (println "DEBUG: HTML parsed successfully, dom type=" (type dom))
      ;; Debug: check what elements are in the DOM
      (let [all-divs (safe-select (s/tag :div) dom)]
        (println "DEBUG: Found " (count all-divs) " div elements"))
      (let [all-tables (safe-select (s/tag :table) dom)]
        (println "DEBUG: Found " (count all-tables) " table elements"))
      (let [all-tr (safe-select (s/tag :tr) dom)]
        (println "DEBUG: Found " (count all-tr) " tr elements"))
      (let [all-td (safe-select (s/tag :td) dom)]
        (println "DEBUG: Found " (count all-td) " td elements"))
      (if (nil? dom)
        {}
        (let [tables (safe-select (s/tag :table) dom)]
          (println "DEBUG: Found " (count tables) " tables")
          (println "DEBUG: Looking for table elements in HTML...")
          ;; Debug: check if there are any table-related elements
          (let [all-elements (safe-select (s/descendant (s/tag :body) (s/tag :table)) dom)]
            (println "DEBUG: Found " (count all-elements) " table elements via descendant selector"))
          (let [divs-with-tables (safe-select (s/tag :div) dom)]
            (println "DEBUG: Found " (count divs-with-tables) " div elements - checking for table-like content"))
          (if (empty? tables)
            {}
            (let [attendance-table (first (filter #(when-let [attrs (:attrs %)]
                                                     (when-let [classes (:class attrs)]
                                                       (str/includes? classes "linkDescList")))
                                                  tables))]
              (println "DEBUG: Attendance table found:" (not (nil? attendance-table)))
              (if (nil? attendance-table)
                {}
                (let [rows (safe-select (s/tag :tr) attendance-table)
                      data-rows (drop 2 rows)]
                  (println "DEBUG: Found " (count rows) " rows, processing " (count data-rows) " data rows")
                  (into {}
                        (keep (fn [row]
                                (try
                                  (let [cells (safe-select (s/tag :td) row)
                                        cell-texts (mapv extract-text-content cells)]
                                    (when (>= (count cell-texts) 17)
                                      ;; The attendance table structure:
                                      ;; Col 11: Course name
                                      ;; Col 12: S2 grade
                                      ;; Col 13: P1 grade
                                      ;; Col 14: S1 grade
                                      ;; Col 15: Absences
                                      ;; Col 16: Tardies
                                      (let [course-cell (extract-course-name (nth cell-texts 11 ""))
                                            s2-cell (str/trim (nth cell-texts 12 ""))
                                            p1-cell (str/trim (nth cell-texts 13 ""))
                                            s1-cell (str/trim (nth cell-texts 14 ""))
                                            abs-cell (str/trim (nth cell-texts 15 ""))
                                            tar-cell (str/trim (nth cell-texts 16 ""))]
                                        (when-not (or (str/blank? course-cell)
                                                      (str/includes? course-cell "Attendance Totals"))
                                          (println "DEBUG: Attendance row - course:" course-cell "s2:" s2-cell "p1:" p1-cell "s1:" s1-cell)
                                          [course-cell {:s2 (extract-grade-value s2-cell)
                                                        :p1 (extract-grade-value p1-cell)
                                                        :s1 (extract-grade-value s1-cell)
                                                        :absences abs-cell
                                                        :tardies tar-cell}]))))
                                  (catch Exception e
                                    (println "DEBUG: Row processing error:" (.getMessage e))
                                    nil)))
                              data-rows)))))))))
    (catch Exception e
      (println "DEBUG: parse-attendance-table exception:" (.getMessage e))
      (.printStackTrace e)
      (throw (Exception. (str "Failed to parse attendance table: " (.getMessage e)))))))

(defn parse-attendance-table-links
  "Extract grade links (hrefs) from attendance table for each course"
  [html]
  (try
    (when (or (nil? html) (not (string? html)))
      (throw (Exception. (str "HTML input invalid: " (type html)))))
    (let [dom (hickory/as-hickory (hickory/parse html))
          tables (safe-select (s/tag :table) dom)
          attendance-table (first (filter #(when-let [attrs (:attrs %)]
                                             (when-let [classes (:class attrs)]
                                               (str/includes? classes "linkDescList")))
                                          tables))]
      (if (nil? attendance-table)
        {}
        (let [rows (safe-select (s/tag :tr) attendance-table)
              header-rows (take 2 rows)
              data-rows (drop 2 rows)]
          ;; Debug header rows
          (doseq [header-row header-rows]
            (let [cells (safe-select (s/tag :td) header-row)
                  cell-texts (mapv extract-text-content cells)]
              (println "DEBUG: Header row:" cell-texts)))
          (into {}
                (keep (fn [row]
                        (try
                          (let [cells (safe-select (s/tag :td) row)
                                cell-count (count cells)]
                            (println "DEBUG: Row cell count:" cell-count)
                            (when (>= cell-count 17)
                              ;; Col 11: Course name
                              ;; Col 12: S2 grade (with link)
                              ;; Col 13: P1 grade (with link)
                              ;; Col 14: S1 grade (with link)
                              (let [course-cell (nth cells 11 nil)
                                    s2-cell (nth cells 12 nil)
                                    p1-cell (nth cells 13 nil)
                                    s1-cell (nth cells 14 nil)
                                    course-name (extract-course-name (extract-text-content course-cell))]
                                (println "DEBUG: Processing course:" course-name "cell-count:" cell-count)
                                ;; Extract hrefs from <a> tags in grade cells
                                (let [s2-link (when s2-cell
                                                (let [links (safe-select (s/tag :a) s2-cell)]
                                                  (when (seq links)
                                                    (get-in (first links) [:attrs :href]))))
                                      p1-link (when p1-cell
                                                (let [links (safe-select (s/tag :a) p1-cell)]
                                                  (when (seq links)
                                                    (get-in (first links) [:attrs :href]))))
                                      s1-link (when s1-cell
                                                (let [links (safe-select (s/tag :a) s1-cell)]
                                                  (when (seq links)
                                                    (get-in (first links) [:attrs :href]))))]
                                  (when-not (or (str/blank? course-name)
                                                (str/includes? course-name "Attendance Totals"))
                                    (println "DEBUG: Attendance links - course:" course-name "S2:" s2-link "P1:" p1-link "S1:" s1-link)
                                    [course-name {:s2-link s2-link
                                                  :p1-link p1-link
                                                  :s1-link s1-link}])))))
                          (catch Exception e
                            (println "DEBUG: Row processing error:" (.getMessage e))
                            nil)))
                      data-rows)))))
    (catch Exception e
      (println "DEBUG: parse-attendance-table-links exception:" (.getMessage e))
      {})))

(defn parse-term-grades-page [html]
  (try
    (when (or (nil? html) (not (string? html)))
      (throw (Exception. (str "HTML input invalid: " (type html)))))
    (let [dom (try
                (hickory/as-hickory (hickory/parse html))
                (catch Exception e
                  (throw (Exception. (str "HTML parsing failed: " (.getMessage e))))))]
      (if (nil? dom)
        {}
        (let [tables (safe-select (s/tag :table) dom)]
          (if (empty? tables)
            {}
            (let [grade-table (first tables)]
              (if (nil? grade-table)
                {}
                (let [rows (safe-select (s/tag :tr) grade-table)
                      ;; Skip header rows (contain th elements instead of just td)
                      data-rows (filter #(let [cells (safe-select (s/tag :td) %)]
                                           (seq cells))
                                        rows)]
                  ;; Accumulate grades by course - multiple rows per course (one per term)
                  (let [grades-by-course (reduce (fn [acc row]
                                                   (try
                                                     (let [cells (safe-select (s/tag :td) row)
                                                           cell-texts (mapv extract-text-content cells)]
                                                       (when (>= (count cell-texts) 5)
                                                         ;; Table: Course | Teacher | Expression | Term | Final Grade
                                                         (let [raw-course (str/trim (first cell-texts))
                                                               course-name (extract-course-name raw-course)
                                                               grade-text (str/trim (nth cell-texts 4 ""))]
                                                           (when-not (str/blank? course-name)
                                                             (println "DEBUG: Term grade row - course:" course-name "grade:" grade-text)
                                                             ;; Accumulate grades for this course into a vector
                                                             (update acc course-name
                                                                     (fn [existing]
                                                                       (let [grade-obj {:grade (extract-grade-value grade-text)}]
                                                                         (if (nil? existing)
                                                                           [grade-obj]
                                                                           (conj existing grade-obj)))))))))
                                                     (catch Exception e
                                                       (println "DEBUG: Error parsing term grade row:" (.getMessage e))
                                                       acc)))
                                                 {}
                                                 data-rows)]
                    (println "DEBUG: Parsed term grades - total classes:" (count grades-by-course) "classes:" (keys grades-by-course))
                    grades-by-course))))))))    (catch Exception e
                                                  (throw (Exception. (str "Failed to parse term grades: " (.getMessage e)))))))

(defn parse-scores-page-metadata
  "Parse scores page HTML to extract API parameters from data attributes"
  [html url-params]
  (try
    (when (or (nil? html) (not (string? html)))
      (throw (Exception. (str "HTML input invalid: " (type html)))))
    (let [dom (hickory/as-hickory (hickory/parse html))
          ;; Find the div with data attributes
          wrapper-divs (safe-select (s/class "xteContentWrapper") dom)
          wrapper (first wrapper-divs)]
      (if (nil? wrapper)
        {:error "Could not find xteContentWrapper div"}
        (let [attrs (:attrs wrapper)
              _ (println "DEBUG: wrapper attrs keys:" (keys attrs))
              _ (println "DEBUG: data attrs:" (filter #(str/starts-with? (name (key %)) "data-") attrs))
              ;; Find the inner div with data-pss-student-assignment-scores
              inner-div (first (safe-select (s/attr "data-pss-student-assignment-scores") dom))
              _ (when inner-div
                  (let [inner-attrs (:attrs inner-div)
                        data-sectionid (get inner-attrs :data-sectionid)
                        data-termid (get inner-attrs :data-termid)]
                    (println "DEBUG: inner div data-sectionid:" data-sectionid "data-termid:" data-termid)))
              ;; Extract data-ng-init attribute which contains the variables
              ng-init (get attrs :data-ng-init "")
              _ (println "DEBUG: ng-init:" ng-init)
              _ (let [section-match (re-find #"section.?id['\":\s]*([^'\"\s]+)" html)]
                  (when section-match
                    (println "DEBUG: found section in HTML:" (second section-match))))
              ;; Parse out the values using regex
              student-frn (second (re-find #"studentFRN\s*=\s*'([^']+)'" ng-init))
              section-id-match (re-find #"section.?id\s*[:=]\s*['\"]([^'\"]+)['\"]" ng-init)
              ;; Get section-id from inner div data-sectionid first
              section-id (or (when inner-div
                               (get (:attrs inner-div) :data-sectionid))
                             (when section-id-match (second section-id-match))
                             (get url-params "frn"))
              ;; Extract from URL params or ng-init (begdate, enddate)
              begdate (or (get url-params "begdate")
                          (second (re-find #"beg(date|inningDate)\s*[:=]\s*['\"]([^'\"]+)['\"]" ng-init)))
              enddate (or (get url-params "enddate")
                          (second (re-find #"end(date|ingDate)\s*[:=]\s*['\"]([^'\"]+)['\"]" ng-init)))
              stored-date (let [sd (second (re-find #"storedDate\s*[:=]\s*['\"]([^'\"]+)['\"]" ng-init))]
                            (when (and sd (not= sd "0")) sd))
              is-stored (let [is (second (re-find #"isStored\s*[:=]\s*['\"]([^'\"]+)['\"]" ng-init))]
                          (= is "true"))
              storecode (second (re-find #"storecode\s*[:=]\s*['\"]([^'\"]+)['\"]" ng-init))
              ;; Convert student FRN to student ID by removing first 3 chars
              student-id (when student-frn (subs student-frn 3))]
          (println "DEBUG: Parsed metadata - student-frn:" student-frn "student-id:" student-id "section-id:" section-id "dates:" begdate enddate "stored:" stored-date "is-stored:" is-stored "storecode:" storecode)
          {:student-id student-id
           :section-id section-id
           :start-date begdate
           :end-date enddate
           :stored-date stored-date
           :is-stored is-stored
           :storecode storecode})))
    (catch Exception e
      (println "DEBUG: parse-scores-page-metadata exception:" (.getMessage e))
      {:error (.getMessage e)})))

(defn parse-url-params
  "Parse query string parameters from URL"
  [url]
  (try
    (let [query-string (second (str/split url #"\?"))
          params (when query-string
                   (str/split query-string #"&"))
          param-map (reduce (fn [m param]
                              (let [[k v] (str/split param #"=")]
                                (assoc m k v)))
                            {}
                            (or params []))]
      param-map)
    (catch Exception e
      (println "DEBUG: parse-url-params error:" (.getMessage e))
      {})))

(defn format-date-for-api
  "Convert date from MM/DD/YYYY to YYYY-M-D format"
  [date-str]
  (try
    (when date-str
      (let [parts (str/split date-str #"/")
            month (Integer/parseInt (first parts))
            day (Integer/parseInt (second parts))
            year (nth parts 2)]
      ; e.g. 2026-1-5  
        (format "%s-%d-%d" year month day)))
    (catch Exception e
      (println "DEBUG: format-date-for-api error:" (.getMessage e))
      nil)))

(defn fetch-assignments-via-api
  "Fetch assignments using PowerSchool's assignment lookup API via browser"
  [driver ps-base student-id section-id start-date end-date stored-date is-stored storecode referer]
  (try
    (when (or (nil? ps-base) (nil? student-id) (nil? section-id))
      (throw (Exception. "Missing required parameters")))
    ;; Convert dates to API format (YYYY-M-D)
    (let [api-start-date (format-date-for-api start-date)
          api-end-date (format-date-for-api end-date)
          api-stored-date (format-date-for-api stored-date)
          timestamp (System/currentTimeMillis)
          url (str "https://" ps-base ".powerschool.com/ws/xte/assignment/lookup?_=" timestamp)
          body-json (cheshire.core/generate-string
                     (cond-> {:section_ids [(Integer/parseInt section-id)]
                              :student_ids [(Integer/parseInt student-id)]}
                       is-stored (assoc :start_date api-stored-date
                                        :end_date api-stored-date)
                       (not is-stored) (assoc :store_codes [storecode])))
          headers {"content-type" "application/json;charset=UTF-8"
                   "accept" "application/json, text/plain, */*"
                   "origin" (str "https://" ps-base ".powerschool.com")
                   "referrer" referer
                   "dnt" "1"
                   "user-agent" "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36"
                   "sec-ch-ua" "\"Not(A:Brand\";v=\"8\", \"Chromium\";v=\"144\", \"Google Chrome\";v=\"144\""
                   "sec-ch-ua-mobile" "?0"
                   "sec-ch-ua-platform" "\"Linux\""
                   "sec-fetch-dest" "empty"
                   "sec-fetch-mode" "cors"
                   "sec-fetch-site" "same-origin"}
          ;; Create XMLHttpRequest script
          xhr-script (str "
            var xhr = new XMLHttpRequest();
            xhr.open('POST', '" url "', false);
            " (apply str (map (fn [[k v]] (str "xhr.setRequestHeader('" k "', '" v "'); ")) headers)) "
            xhr.send('" (str/replace body-json "'" "\\'") "');
            if (xhr.status >= 200 && xhr.status < 300) {
              return JSON.parse(xhr.responseText);
            } else {
              throw new Error('HTTP ' + xhr.status + ': ' + xhr.responseText);
            }
          ")]
      (println "DEBUG: API request - student:" student-id "section:" section-id "dates:" api-start-date "to" api-end-date "stored:" api-stored-date)
      (let [assignments (etaoin/js-execute driver xhr-script)]
        (println "DEBUG: API returned" (count assignments) "assignments")
        ;; Transform to simplified format
        (vec (keep (fn [assignment]
                     (let [assignment-section (first (:_assignmentsections assignment))
                           assignment-score (first (:_assignmentscores assignment-section))
                           category-assoc (first (:_assignmentcategoryassociations assignment-section))
                           teacher-category (:_teachercategory category-assoc)]
                       (when (and assignment-section assignment-score)
                         {:assignment (:name assignment-section)
                          :due-date (:duedate assignment-section)
                          :category (:name teacher-category)
                          :score-points (:scorepoints assignment-score)
                          :total-points (:totalpointvalue assignment-section)
                          :score-percent (:scorepercent assignment-score)
                          :letter-grade (:scorelettergrade assignment-score)
                          :is-late (:islate assignment-score)
                          :is-missing (:ismissing assignment-score)
                          :is-incomplete (:isincomplete assignment-score)})))))))))

(defn fetch-scores-page
  "Fetch assignments by first parsing scores page metadata, then calling API"
  [driver ps-base scores-href]
  (try
    (when (or (nil? ps-base) (nil? scores-href))
      (throw (Exception. "Missing required parameters")))
    ;; scores-href is relative like "scores.html?frn=..."
    (let [full-url (str "https://" ps-base ".powerschool.com/guardian/" scores-href)
          url-params (parse-url-params scores-href)]
      (etaoin/go driver full-url)
      (etaoin/wait-visible driver {:css "body"} {:timeout 5000})
      (let [body (etaoin/get-source driver)]
        (let [metadata (parse-scores-page-metadata body url-params)]
          (if (:error metadata)
            (do
              (println "DEBUG: Failed to parse metadata, error:" (:error metadata))
              [])
            (let [student-id (:student-id metadata)
                  section-id (:section-id metadata)
                  start-date (:start-date metadata)
                  end-date (:end-date metadata)
                  stored-date (:stored-date metadata)
                  is-stored (:is-stored metadata)
                  storecode (:storecode metadata)]
              (println "DEBUG: Using metadata - student-id:" student-id "section-id:" section-id "start:" start-date "end:" end-date "stored:" stored-date "is-stored:" is-stored "storecode:" storecode)
              (fetch-assignments-via-api driver ps-base student-id section-id start-date end-date stored-date is-stored storecode full-url))))))
    (catch Exception e
      (println "DEBUG: fetch-scores-page exception:" (.getMessage e)))))


(defn fetch-term-grades [cookies ps-base]
  (try
    (when (or (nil? ps-base) (nil? cookies))
      (throw (Exception. "ps-base or cookies is null")))

    ;; Convert cookies to header string instead of passing as :cookies
    (let [cookie-header (cookies-to-header cookies)]
      (when (empty? cookie-header)
        (throw (Exception. "No valid cookies after conversion")))

      (let [url (str "https://" ps-base ".powerschool.com/guardian/termgrades.html")
            response (client/get url
                                 {:headers {"Cookie" cookie-header}
                                  :throw-exceptions false
                                  :follow-redirects true})
            status (:status response)
            body (:body response)]
        (when (or (nil? status) (>= status 400))
          (throw (Exception. (str "HTTP error: status " status))))
        (if (or (nil? body) (not (string? body)))
          (throw (Exception. (str "Response body invalid: " (type body))))
          (do
            ;; Check if we were redirected to the login page (authentication failed)
            (when (str/includes? body "Student and Parent Sign In")
              (throw (Exception. "Authentication failed - session expired or invalid cookies")))
            (parse-term-grades-page body)))))
    (catch Exception e
      {:error (.getMessage e)})))

(defn parse-attendance-history-summary [html]
  (try
    (when (or (nil? html) (not (string? html)))
      (throw (Exception. (str "HTML input invalid: " (type html)))))
    (let [dom (try
                (hickory/as-hickory (hickory/parse html))
                (catch Exception e
                  (throw (Exception. (str "HTML parsing failed: " (.getMessage e))))))]
      (if (nil? dom)
        {}
        (let [rows (safe-select (s/tag :tr) dom)
              total-row (first (filter #(let [cells (safe-select (s/tag :td) %)]
                                          (some (fn [cell]
                                                  (let [text (extract-text-content cell)]
                                                    (str/includes? text "Attendance Totals")))
                                                cells))
                                       rows))]
          (if total-row
            (let [cells (safe-select (s/tag :td) total-row)
                  cell-texts (mapv extract-text-content cells)]
              (if (>= (count cell-texts) 2)
                {:absences (str/trim (nth cell-texts (- (count cell-texts) 2) ""))
                 :tardies (str/trim (nth cell-texts (- (count cell-texts) 1) ""))}
                {}))
            {}))))
    (catch Exception e
      {:error (.getMessage e)})))

(defn compile-all-grades [cookies ps-base]
  (try
    (println "DEBUG: compile-all-grades starting with ps-base=" ps-base)
    (let [home-page (try
                      (do
                        (println "DEBUG: Calling fetch-grades-page...")
                        (let [result (fetch-grades-page cookies ps-base)]
                          (println "DEBUG: fetch-grades-page returned type=" (type result) " length=" (if (string? result) (count result) "not-string"))
                          result))
                      (catch Exception e
                        (println "DEBUG: fetch-grades-page failed:" (.getMessage e))
                        (.printStackTrace e)
                        (throw e)))
          current-grades (try
                           (do
                             (println "DEBUG: Calling parse-attendance-table with home-page type=" (type home-page))
                             (parse-attendance-table home-page))
                           (catch Exception e
                             (println "DEBUG: parse-attendance-table failed:" (.getMessage e))
                             {:error (str "Attendance parsing failed: " (.getMessage e))}))
          term-grades (try
                        (do
                          (println "DEBUG: Calling fetch-term-grades...")
                          (fetch-term-grades cookies ps-base))
                        (catch Exception e
                          (println "DEBUG: fetch-term-grades failed:" (.getMessage e))
                          {:error (str "Term grades fetch failed: " (.getMessage e))}))]
      (println "DEBUG: All fetches complete, returning results")
      {:current current-grades
       :term-history term-grades
       :last-updated (java.time.Instant/now)})
    (catch Exception e
      (println "DEBUG: compile-all-grades exception:" (.getMessage e))
      (.printStackTrace e)
      {:error (.getMessage e)})))

(defn normalize-class-name
  "Normalize class name by removing all whitespace variations and converting to lowercase"
  [class-name]
  (-> class-name
      ;; Replace all types of whitespace (including non-breaking spaces \u00A0) with regular space
      (str/replace #"[\s\u00A0]+" " ")
      str/trim
      str/lower-case))

(defn fetch-class-grade-history [driver ps-base class-name]
  "Fetch grade history for a single class by following attendance page links"
  (try
    (println "DEBUG: fetch-class-grade-history starting - class:" class-name " ps-base=" ps-base)
    (when (or (nil? ps-base) (nil? class-name))
      (throw (Exception. "Missing required parameters")))

    ;; Navigate to attendance page to get grade links
    (let [url (str "https://" ps-base ".powerschool.com/guardian/home.html")]
      (etaoin/go driver url)
      (etaoin/wait-visible driver {:css "body"} {:timeout 5000})
      (let [body (etaoin/get-source driver)]

        ;; Parse attendance table to get grade links
        (let [all-links (parse-attendance-table-links body)
              ;; Normalize for case-insensitive matching with whitespace handling
              normalized-class-name (normalize-class-name class-name)
              normalized-links (into {} (map (fn [[k v]] [(normalize-class-name k) v]) all-links))
              class-links (get normalized-links normalized-class-name)]

          (println "DEBUG: fetch-class-grade-history - requested:" class-name "(normalized:" normalized-class-name ")")
          (println "DEBUG: Available classes:" (keys all-links))

          (if (nil? class-links)
            {:error (str "Class not found: " class-name)
             :available (keys all-links)}
            (let [{:keys [s2-link p1-link s1-link]} class-links]
              (println "DEBUG: Found links for" class-name "- S2:" s2-link "P1:" p1-link "S1:" s1-link)
              ;; Fetch grades in priority order: S2, P1, S1
              (let [grades (vec (keep identity
                                      [(when s2-link
                                         (println "DEBUG: Fetching S2 assignments...")
                                         (let [assignments (fetch-scores-page driver ps-base s2-link)]
                                           (println "DEBUG: S2 fetched" (count assignments) "assignments")
                                           (when (seq assignments)
                                             {:term "S2" :assignments assignments})))
                                       (when p1-link
                                         (println "DEBUG: Fetching P1 assignments...")
                                         (let [assignments (fetch-scores-page driver ps-base p1-link)]
                                           (println "DEBUG: P1 fetched" (count assignments) "assignments")
                                           (when (seq assignments)
                                             {:term "P1" :assignments assignments})))
                                       (when s1-link
                                         (println "DEBUG: Fetching S1 assignments...")
                                         (let [assignments (fetch-scores-page driver ps-base s1-link)]
                                           (println "DEBUG: S1 fetched" (count assignments) "assignments")
                                           (when (seq assignments)
                                             {:term "S1" :assignments assignments})))]))]
                (println "DEBUG: Fetched" (count grades) "terms with assignments")
                {:class-name class-name
                 :grades grades
                 :last-updated (java.time.Instant/now)}))))))
    (catch Exception e
      (println "DEBUG: fetch-class-grade-history exception:" (.getMessage e)))))