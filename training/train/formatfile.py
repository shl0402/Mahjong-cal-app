import os
import pandas as pd
from shutil import copyfile
from sklearn.model_selection import train_test_split

# Paths
csv_file = 'train/data.csv'  # Path to your CSV file
image_dir = 'train/images/'          # Directory containing images
output_dir = 'train/dataset/'       # Output directory for YOLO-formatted data

# Create necessary directories
os.makedirs(os.path.join(output_dir, 'images/train'), exist_ok=True)
os.makedirs(os.path.join(output_dir, 'images/val'), exist_ok=True)
os.makedirs(os.path.join(output_dir, 'labels/train'), exist_ok=True)
os.makedirs(os.path.join(output_dir, 'labels/val'), exist_ok=True)

# Load CSV
df = pd.read_csv(csv_file)

# Split data into training and validation sets (e.g., 80% train, 20% val)
train_df, val_df = train_test_split(df, test_size=0.2, random_state=42)

def process_data(dataframe, subset):
    for _, row in dataframe.iterrows():
        image_name = row['image-name']
        class_id = row['label']

        # Define source and destination paths
        src_image_path = os.path.join(image_dir, image_name)
        dst_image_path = os.path.join(output_dir, f'images/{subset}', image_name)
        label_path = os.path.join(output_dir, f'labels/{subset}', image_name.replace('.jpg', '.txt'))

        # Copy image to the appropriate directory
        if os.path.exists(src_image_path):
            copyfile(src_image_path, dst_image_path)
        else:
            print(f"Image {src_image_path} not found, skipping.")
            continue

        # Write label file
        with open(label_path, 'w') as f:
            # Write the class_id and normalized bounding box coordinates
            f.write(f"{class_id} 0.5 0.5 1.0 1.0\n")

# Process training and validation data
process_data(train_df, 'train')
process_data(val_df, 'val')