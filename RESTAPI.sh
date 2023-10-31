#!/bin/bash

# Configuration: Using a user_inputs file that will set up the environmental variables used in this script.
source /home/fred/user_inputs.txt
echo "WP_USERNAME: $WP_USERNAME"
echo "WP_PASSWORD: $WP_PASSWORD"
echo "WP_DOMAIN: $WP_DOMAIN"


# Fetch JWT Authentication Token
TOKEN_RESPONSE=$(curl -d "username=$WP_USERNAME&password=$WP_PASSWORD" -X POST $WP_DOMAIN/wp-json/api/v1/token)



TOKEN=$(echo $TOKEN_RESPONSE | jq -r '.jwt_token')




# If token fetch fails, exit the script
if [ "$TOKEN" == "null" ] || [ -z "$TOKEN" ]; then
    echo "Failed to fetch authentication token."
    exit 1
fi

# Changed url to use the fun_api_url
FACT_RESPONSE=$(curl -s "$FUN_API_URL")
FACT=$(echo $FACT_RESPONSE | jq -r '.value')  # Assumes 'text' key contains the data
# Use the Wordpress API to create a blog post
BLOG_POST_RESPONSE=$(curl -X POST "$WP_DOMAIN/wp-json/wp/v2/posts" \
    -H "Authorization:Bearer $TOKEN" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "title=Random Fact of the Day" \
    -d "content=$FACT" \
    -d "status=publish" \
    -d "categories=$CATEGORY_ID" \
    -d "author=$AUTHOR_ID" \
    -s)

echo "WP_DOMAIN: $WP_DOMAIN"
echo "TOKEN: $TOKEN"
echo "FACT: $FACT"
echo "CATEGORY_ID: $CATEGORY_ID"
echo "AUTHOR_ID: $AUTHOR_ID"

echo "Server Response: $BLOG_POST_RESPONSE"


# Log the response (for debugging purposes)
echo "$BLOG_POST_RESPONSE" >> /var/log/daily_blog_post.log

exit 0
