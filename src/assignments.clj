(ns assignments
  (:gen-class)
  (:require
   [clj-http.client :as client]
   [clojure.string :as str]
   [hickory.core :as hickory]
   [hickory.select :as s]))

(defn extract-text-content
  "Extract text from hickory element, handling nested tags."
  [element]
  (if (string? element)
    element
    (cond
      (nil? element) ""
      (map? element) 
      (if-let [content (:content element)]
        (apply str (map extract-text-content content))
        "")
      (sequential? element)
      (apply str (map extract-text-content element))
      :else (str element))))

(defn fetch-assignments-page [cookies ps-base]
  (try
    (let [response (client/get
                     (format "https://%s.powerschool.com/guardian/home.html" ps-base)
                     {:cookies cookies
                      :throw-exceptions false
                      :follow-redirects true})]
      (:body response))
    (catch Exception e
      (throw (Exception. (str "Failed to fetch assignments page: " (.getMessage e)))))))

(defn parse-assignment-score-link [href]
  (when (and href (str/includes? href "scores.html"))
    (let [params (str/split href #"[?&]")
          param-map (into {}
                          (map (fn [param]
                                 (let [[k v] (str/split param #"=")]
                                   [(str/lower-case k) v]))
                               (rest params)))]
      {:frn (param-map "frn")
       :begdate (param-map "begdate")
       :enddate (param-map "enddate")
       :term (param-map "fg")
       :schoolid (param-map "schoolid")})))

(defn parse-assignments-from-scores-page [html]
  (try
    (let [dom (hickory/as-hickory (hickory/parse html))
          tables (s/select (s/tag :table) dom)]
      (if (seq tables)
        (mapv (fn [row]
                (let [cells (s/select (s/tag :td) row)
                      cell-texts (map extract-text-content cells)]
                  (when (>= (count cell-texts) 4)
                    {:title (nth cell-texts 0)
                     :dueDate (nth cell-texts 1)
                     :category (nth cell-texts 2)
                     :score (nth cell-texts 3)
                     :points (if (>= (count cell-texts) 5) (nth cell-texts 4) "N/A")})))
              (drop 1 (flatten (map #(s/select (s/tag :tr) %) tables))))
        []))
    (catch Exception _
      [])))

(defn fetch-and-parse-assignments [cookies ps-base class-name]
  (try
    (let [_ (fetch-assignments-page cookies ps-base)]
      [])
    (catch Exception e
      [{:error (str "Failed to fetch assignments: " (.getMessage e))
        :class-name class-name}])))

