CREATE FOREIGN TABLE call_center (
    cc_call_center_sk bigint,
    cc_call_center_id text,
    cc_rec_start_date date,
    cc_rec_end_date date,
    cc_closed_date_sk bigint,
    cc_open_date_sk bigint,
    cc_name text,
    cc_class text,
    cc_employees bigint,
    cc_sq_ft bigint,
    cc_hours text,
    cc_manager text,
    cc_mkt_id bigint,
    cc_mkt_class text,
    cc_mkt_desc text,
    cc_market_manager text,
    cc_division bigint,
    cc_division_name text,
    cc_company bigint,
    cc_company_name text,
    cc_street_number text,
    cc_street_name text,
    cc_street_type text,
    cc_suite_number text,
    cc_city text,
    cc_county text,
    cc_state text,
    cc_zip text,
    cc_country text,
    cc_gmt_offset numeric(5,2),
    cc_tax_percentage numeric(5,2)
) SERVER smoke_server
    OPTIONS (table 'tpcds.call_center');

CREATE FOREIGN TABLE catalog_page (
    cp_catalog_page_sk bigint,
    cp_catalog_page_id text,
    cp_start_date_sk bigint,
    cp_end_date_sk bigint,
    cp_department text,
    cp_catalog_number bigint,
    cp_catalog_page_number bigint,
    cp_description text,
    cp_type text
) SERVER smoke_server
    OPTIONS (table 'tpcds.catalog_page');

CREATE FOREIGN TABLE catalog_returns (
    cr_returned_date_sk bigint,
    cr_returned_time_sk bigint,
    cr_item_sk bigint,
    cr_refunded_customer_sk bigint,
    cr_refunded_cdemo_sk bigint,
    cr_refunded_hdemo_sk bigint,
    cr_refunded_addr_sk bigint,
    cr_returning_customer_sk bigint,
    cr_returning_cdemo_sk bigint,
    cr_returning_hdemo_sk bigint,
    cr_returning_addr_sk bigint,
    cr_call_center_sk bigint,
    cr_catalog_page_sk bigint,
    cr_ship_mode_sk bigint,
    cr_warehouse_sk bigint,
    cr_reason_sk bigint,
    cr_order_number bigint,
    cr_return_quantity bigint,
    cr_return_amount numeric(7,2),
    cr_return_tax numeric(7,2),
    cr_return_amt_inc_tax numeric(7,2),
    cr_fee numeric(7,2),
    cr_return_ship_cost numeric(7,2),
    cr_refunded_cash numeric(7,2),
    cr_reversed_charge numeric(7,2),
    cr_store_credit numeric(7,2),
    cr_net_loss numeric(7,2)
) SERVER smoke_server
    OPTIONS (table 'tpcds.catalog_returns');

CREATE FOREIGN TABLE catalog_sales (
    cs_sold_date_sk bigint,
    cs_sold_time_sk bigint,
    cs_ship_date_sk bigint,
    cs_bill_customer_sk bigint,
    cs_bill_cdemo_sk bigint,
    cs_bill_hdemo_sk bigint,
    cs_bill_addr_sk bigint,
    cs_ship_customer_sk bigint,
    cs_ship_cdemo_sk bigint,
    cs_ship_hdemo_sk bigint,
    cs_ship_addr_sk bigint,
    cs_call_center_sk bigint,
    cs_catalog_page_sk bigint,
    cs_ship_mode_sk bigint,
    cs_warehouse_sk bigint,
    cs_item_sk bigint,
    cs_promo_sk bigint,
    cs_order_number bigint,
    cs_quantity bigint,
    cs_wholesale_cost numeric(7,2),
    cs_list_price numeric(7,2),
    cs_sales_price numeric(7,2),
    cs_ext_discount_amt numeric(7,2),
    cs_ext_sales_price numeric(7,2),
    cs_ext_wholesale_cost numeric(7,2),
    cs_ext_list_price numeric(7,2),
    cs_ext_tax numeric(7,2),
    cs_coupon_amt numeric(7,2),
    cs_ext_ship_cost numeric(7,2),
    cs_net_paid numeric(7,2),
    cs_net_paid_inc_tax numeric(7,2),
    cs_net_paid_inc_ship numeric(7,2),
    cs_net_paid_inc_ship_tax numeric(7,2),
    cs_net_profit numeric(7,2)
) SERVER smoke_server
    OPTIONS (table 'tpcds.catalog_sales');

CREATE FOREIGN TABLE customer (
    c_customer_sk bigint,
    c_customer_id text,
    c_current_cdemo_sk bigint,
    c_current_hdemo_sk bigint,
    c_current_addr_sk bigint,
    c_first_shipto_date_sk bigint,
    c_first_sales_date_sk bigint,
    c_salutation text,
    c_first_name text,
    c_last_name text,
    c_preferred_cust_flag text,
    c_birth_day bigint,
    c_birth_month bigint,
    c_birth_year bigint,
    c_birth_country text,
    c_login text,
    c_email_address text,
    c_last_review_date_sk integer
) SERVER smoke_server
    OPTIONS (table 'tpcds.customer');

CREATE FOREIGN TABLE customer_address (
    ca_address_sk bigint,
    ca_address_id text,
    ca_street_number text,
    ca_street_name text,
    ca_street_type text,
    ca_suite_number text,
    ca_city text,
    ca_county text,
    ca_state text,
    ca_zip text,
    ca_country text,
    ca_gmt_offset numeric(5,2),
    ca_location_type text
) SERVER smoke_server
    OPTIONS (table 'tpcds.customer_address');

CREATE FOREIGN TABLE customer_demographics (
    cd_demo_sk bigint,
    cd_gender text,
    cd_marital_status text,
    cd_education_status text,
    cd_purchase_estimate bigint,
    cd_credit_rating text,
    cd_dep_count bigint,
    cd_dep_employed_count bigint,
    cd_dep_college_count integer
) SERVER smoke_server
    OPTIONS (table 'tpcds.customer_demographics');

CREATE FOREIGN TABLE date_dim (
    d_date_sk bigint,
    d_date_id text,
    d_date date,
    d_month_seq bigint,
    d_week_seq bigint,
    d_quarter_seq bigint,
    d_year bigint,
    d_dow bigint,
    d_moy bigint,
    d_dom bigint,
    d_qoy bigint,
    d_fy_year bigint,
    d_fy_quarter_seq bigint,
    d_fy_week_seq bigint,
    d_day_name text,
    d_quarter_name text,
    d_holiday text,
    d_weekend text,
    d_following_holiday text,
    d_first_dom bigint,
    d_last_dom bigint,
    d_same_day_ly bigint,
    d_same_day_lq bigint,
    d_current_day text,
    d_current_week text,
    d_current_month text,
    d_current_quarter text,
    d_current_year text
) SERVER smoke_server
    OPTIONS (table 'tpcds.date_dim');

CREATE FOREIGN TABLE household_demographics (
    hd_demo_sk bigint,
    hd_income_band_sk bigint,
    hd_buy_potential text,
    hd_dep_count bigint,
    hd_vehicle_count integer
) SERVER smoke_server
    OPTIONS (table 'tpcds.household_demographics');

CREATE FOREIGN TABLE income_band (
    ib_income_band_sk bigint,
    ib_lower_bound bigint,
    ib_upper_bound integer
) SERVER smoke_server
    OPTIONS (table 'tpcds.income_band');

CREATE FOREIGN TABLE item (
    i_item_sk bigint,
    i_item_id text,
    i_rec_start_date date,
    i_rec_end_date date,
    i_item_desc text,
    i_current_price numeric(7,2),
    i_wholesale_cost numeric(7,2),
    i_brand_id bigint,
    i_brand text,
    i_class_id bigint,
    i_class text,
    i_category_id bigint,
    i_category text,
    i_manufact_id bigint,
    i_manufact text,
    i_size text,
    i_formulation text,
    i_color text,
    i_units text,
    i_container text,
    i_manager_id bigint,
    i_product_name text
) SERVER smoke_server
    OPTIONS (table 'tpcds.item');

CREATE FOREIGN TABLE promotion (
    p_promo_sk bigint,
    p_promo_id text,
    p_start_date_sk bigint,
    p_end_date_sk bigint,
    p_item_sk bigint,
    p_cost numeric(15,2),
    p_response_target bigint,
    p_promo_name text,
    p_channel_dmail text,
    p_channel_email text,
    p_channel_catalog text,
    p_channel_tv text,
    p_channel_radio text,
    p_channel_press text,
    p_channel_event text,
    p_channel_demo text,
    p_channel_details text,
    p_purpose text,
    p_discount_active text
) SERVER smoke_server
    OPTIONS (table 'tpcds.promotion');

CREATE FOREIGN TABLE reason (
    r_reason_sk bigint,
    r_reason_id text,
    r_reason_desc text
) SERVER smoke_server
    OPTIONS (table 'tpcds.reason');

CREATE FOREIGN TABLE store (
    s_store_sk bigint,
    s_store_id text,
    s_rec_start_date date,
    s_rec_end_date date,
    s_closed_date_sk bigint,
    s_store_name text,
    s_number_employees bigint,
    s_floor_space bigint,
    s_hours text,
    s_manager text,
    s_market_id bigint,
    s_geography_class text,
    s_market_desc text,
    s_market_manager text,
    s_division_id bigint,
    s_division_name text,
    s_company_id bigint,
    s_company_name text,
    s_street_number text,
    s_street_name text,
    s_street_type text,
    s_suite_number text,
    s_city text,
    s_county text,
    s_state text,
    s_zip text,
    s_country text,
    s_gmt_offset numeric(5,2),
    s_tax_percentage numeric(5,2)
) SERVER smoke_server
    OPTIONS (table 'tpcds.store');

CREATE FOREIGN TABLE store_returns (
    sr_returned_date_sk bigint,
    sr_return_time_sk bigint,
    sr_item_sk bigint,
    sr_customer_sk bigint,
    sr_cdemo_sk bigint,
    sr_hdemo_sk bigint,
    sr_addr_sk bigint,
    sr_store_sk bigint,
    sr_reason_sk bigint,
    sr_ticket_number bigint,
    sr_return_quantity bigint,
    sr_return_amt numeric(7,2),
    sr_return_tax numeric(7,2),
    sr_return_amt_inc_tax numeric(7,2),
    sr_fee numeric(7,2),
    sr_return_ship_cost numeric(7,2),
    sr_refunded_cash numeric(7,2),
    sr_reversed_charge numeric(7,2),
    sr_store_credit numeric(7,2),
    sr_net_loss numeric(7,2)
) SERVER smoke_server
    OPTIONS (table 'tpcds.store_returns');

CREATE FOREIGN TABLE store_sales (
    ss_sold_date_sk bigint,
    ss_sold_time_sk bigint,
    ss_item_sk bigint,
    ss_customer_sk bigint,
    ss_cdemo_sk bigint,
    ss_hdemo_sk bigint,
    ss_addr_sk bigint,
    ss_store_sk bigint,
    ss_promo_sk bigint,
    ss_ticket_number bigint,
    ss_quantity bigint,
    ss_wholesale_cost numeric(7,2),
    ss_list_price numeric(7,2),
    ss_sales_price numeric(7,2),
    ss_ext_discount_amt numeric(7,2),
    ss_ext_sales_price numeric(7,2),
    ss_ext_wholesale_cost numeric(7,2),
    ss_ext_list_price numeric(7,2),
    ss_ext_tax numeric(7,2),
    ss_coupon_amt numeric(7,2),
    ss_net_paid numeric(7,2),
    ss_net_paid_inc_tax numeric(7,2),
    ss_net_profit numeric(7,2)
) SERVER smoke_server
    OPTIONS (table 'tpcds.store_sales');

CREATE FOREIGN TABLE time_dim (
    t_time_sk bigint,
    t_time_id text,
    t_time bigint,
    t_hour bigint,
    t_minute bigint,
    t_second bigint,
    t_am_pm text,
    t_shift text,
    t_sub_shift text,
    t_meal_time text
) SERVER smoke_server
    OPTIONS (table 'tpcds.time_dim');

CREATE FOREIGN TABLE warehouse (
    w_warehouse_sk bigint,
    w_warehouse_id text,
    w_warehouse_name text,
    w_warehouse_sq_ft bigint,
    w_street_number text,
    w_street_name text,
    w_street_type text,
    w_suite_number text,
    w_city text,
    w_county text,
    w_state text,
    w_zip text,
    w_country text,
    w_gmt_offset numeric(5,2)
) SERVER smoke_server
    OPTIONS (table 'tpcds.warehouse');

CREATE FOREIGN TABLE web_page (
    wp_web_page_sk bigint,
    wp_web_page_id text,
    wp_rec_start_date date,
    wp_rec_end_date date,
    wp_creation_date_sk bigint,
    wp_access_date_sk bigint,
    wp_autogen_flag text,
    wp_customer_sk bigint,
    wp_url text,
    wp_type text,
    wp_char_count bigint,
    wp_link_count bigint,
    wp_image_count bigint,
    wp_max_ad_count integer
) SERVER smoke_server
    OPTIONS (table 'tpcds.web_page');

CREATE FOREIGN TABLE web_returns (
    wr_returned_date_sk bigint,
    wr_returned_time_sk bigint,
    wr_item_sk bigint,
    wr_refunded_customer_sk bigint,
    wr_refunded_cdemo_sk bigint,
    wr_refunded_hdemo_sk bigint,
    wr_refunded_addr_sk bigint,
    wr_returning_customer_sk bigint,
    wr_returning_cdemo_sk bigint,
    wr_returning_hdemo_sk bigint,
    wr_returning_addr_sk bigint,
    wr_web_page_sk bigint,
    wr_reason_sk bigint,
    wr_order_number bigint,
    wr_return_quantity bigint,
    wr_return_amt numeric(7,2),
    wr_return_tax numeric(7,2),
    wr_return_amt_inc_tax numeric(7,2),
    wr_fee numeric(7,2),
    wr_return_ship_cost numeric(7,2),
    wr_refunded_cash numeric(7,2),
    wr_reversed_charge numeric(7,2),
    wr_account_credit numeric(7,2),
    wr_net_loss numeric(7,2)
) SERVER smoke_server
    OPTIONS (table 'tpcds.web_returns');

CREATE FOREIGN TABLE web_sales (
    ws_sold_date_sk bigint,
    ws_sold_time_sk bigint,
    ws_ship_date_sk bigint,
    ws_item_sk bigint,
    ws_bill_customer_sk bigint,
    ws_bill_cdemo_sk bigint,
    ws_bill_hdemo_sk bigint,
    ws_bill_addr_sk bigint,
    ws_ship_customer_sk bigint,
    ws_ship_cdemo_sk bigint,
    ws_ship_hdemo_sk bigint,
    ws_ship_addr_sk bigint,
    ws_web_page_sk bigint,
    ws_web_site_sk bigint,
    ws_ship_mode_sk bigint,
    ws_warehouse_sk bigint,
    ws_promo_sk bigint,
    ws_order_number bigint,
    ws_quantity bigint,
    ws_wholesale_cost numeric(7,2),
    ws_list_price numeric(7,2),
    ws_sales_price numeric(7,2),
    ws_ext_discount_amt numeric(7,2),
    ws_ext_sales_price numeric(7,2),
    ws_ext_wholesale_cost numeric(7,2),
    ws_ext_list_price numeric(7,2),
    ws_ext_tax numeric(7,2),
    ws_coupon_amt numeric(7,2),
    ws_ext_ship_cost numeric(7,2),
    ws_net_paid numeric(7,2),
    ws_net_paid_inc_tax numeric(7,2),
    ws_net_paid_inc_ship numeric(7,2),
    ws_net_paid_inc_ship_tax numeric(7,2),
    ws_net_profit numeric(7,2)
) SERVER smoke_server
    OPTIONS (table 'tpcds.web_sales');

CREATE FOREIGN TABLE web_site (
    web_site_sk bigint,
    web_site_id text,
    web_rec_start_date date,
    web_rec_end_date date,
    web_name text,
    web_open_date_sk bigint,
    web_close_date_sk bigint,
    web_class text,
    web_manager text,
    web_mkt_id bigint,
    web_mkt_class text,
    web_mkt_desc text,
    web_market_manager text,
    web_company_id bigint,
    web_company_name text,
    web_street_number text,
    web_street_name text,
    web_street_type text,
    web_suite_number text,
    web_city text,
    web_county text,
    web_state text,
    web_zip text,
    web_country text,
    web_gmt_offset numeric(5,2),
    web_tax_percentage numeric(5,2)
) SERVER smoke_server
    OPTIONS (table 'tpcds.web_site');
