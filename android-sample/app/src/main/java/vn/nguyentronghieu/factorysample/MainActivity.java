package vn.nguyentronghieu.factorysample;

import android.app.Activity;
import android.os.Bundle;
import android.os.StatFs;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import java.io.File;

public final class MainActivity extends Activity {
    private TextView status;

    @Override
    public void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        int padding = (int) (24 * getResources().getDisplayMetrics().density);
        layout.setPadding(padding, padding, padding, padding);

        status = new TextView(this);
        layout.addView(status);
        Button clean = new Button(this);
        clean.setText("Dọn bộ nhớ đệm của app này");
        clean.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View view) {
                long removed = clearOwnCache(getCacheDir());
                status.setText("Đã dọn " + removed + " byte trong cache riêng.\n" + freeSpace());
            }
        });
        layout.addView(clean);
        setContentView(layout);
        status.setText(freeSpace());
    }

    private String freeSpace() {
        StatFs disk = new StatFs(getFilesDir().getPath());
        return "Bộ nhớ trống: " + (disk.getAvailableBytes() / (1024 * 1024)) + " MB";
    }

    private long clearOwnCache(File directory) {
        long removed = 0;
        File[] children = directory.listFiles();
        if (children == null) return 0;
        for (File child : children) {
            if (child.isDirectory()) removed += clearOwnCache(child);
            else {
                long size = child.length();
                if (child.delete()) removed += size;
            }
        }
        return removed;
    }
}
