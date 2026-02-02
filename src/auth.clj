; Authentication microservice for PowerSchoolWrap

 (ns auth
   (:gen-class)
   (:require
    [clojure.string :as str]
    [etaoin.api :as etaoin]
    [clj-http.client :as http]))

(defn undetectable-chromedriver
  "Create an undetectable Chrome driver instance."
  []
  (etaoin/chrome-headless {:args ["--no-sandbox" "--disable-dev-shm-usage"
                                  "--headless" "--disable-gpu"
                                  "--disable-blink-features=AutomationControlled"
                                  "--disable-infobars"
                                  "--disable-extensions"
                                  "--profile-directory=Default"
                                  "--disable-plugins-discovery"
                                  "--incognito"
                                  "--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/85.0.4183.102 Safari/537.36"]
                           :prefs {"credentials_enable_service" false
                                   "profile.password_manager_enabled" false}
                           :path-browser "/usr/bin/google-chrome-beta"
                           :driver-version "145.0.7632.18"}))

(defn- cookies->map
  "Convert etaoin cookies to a safe string-keyed map.
  Filters out nil/blank names and nil values."
  [cookies]
  (->> (or cookies [])
       (filter #(and (some? (:name %))
                     (not (str/blank? (str (:name %))))
                     (some? (:value %))))
       (map (fn [c] [(str (:name c)) (str (:value c))]))
       (into {})))

(defn authenticate-user
  "Authenticate user against PowerSchool and return session cookies."
  [username password ps-base]
  (when (or (nil? ps-base) (empty? (clojure.string/trim ps-base)))
    (throw (Exception. "PS Base is required and cannot be empty")))
  (let [driver (undetectable-chromedriver)
        login-url (str "https://" ps-base ".powerschool.com/guardian/home.html")]
    (etaoin/go driver (str "https://" ps-base ".powerschool.com/public/home.html"))
    (let [cookie-names ["JSESSIONID" "reese84"]]
      (while (not (every? #(some (fn [c] (= (:name c) %)) (or (etaoin/get-cookies driver) [])) cookie-names))
        (Thread/sleep 500)))
    (try
      (let [cookie-map (cookies->map (etaoin/get-cookies driver))]
        (etaoin/go driver login-url)
        (etaoin/wait-visible driver {:css "input[name='account']"} {:timeout 5000})
        (etaoin/fill driver {:css "input[name='account']"} username)
        (etaoin/fill driver {:css "input[name='pw']"} password)
        (etaoin/click driver {:css "button[type='submit']"})
        (etaoin/wait-visible driver {:css "body"} {:timeout 5000})
        (let [post-login-cookies (cookies->map (etaoin/get-cookies driver))]
          (if (and (contains? post-login-cookies "JSESSIONID")
                   (not= (get cookie-map "JSESSIONID") (get post-login-cookies "JSESSIONID")))
            post-login-cookies
            (throw (Exception. "Invalid username or password")))))
      (catch Exception e
        (throw (Exception. (str "Authentication failed: " (.getMessage e)))))
      (finally
        (etaoin/quit driver)))))